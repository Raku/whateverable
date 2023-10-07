#!/usr/bin/env perl6
# Copyright © 2016-2023
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
# Copyright © 2016
#     Daniel Green <ddgreen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Whateverable;
use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Config;
use Whateverable::Running;

use File::Directory::Tree;
use IRC::Client;
use JSON::Fast;
use SVG;
use SVG::Plot;

unit class Statisfiable does Whateverable;

%*BOT-ENV = %(
    #range      => ‘2014.01..HEAD’,
    range      => ‘f3baa389d98..da5825e698720’,
    background => ‘white’,
    width      => 1000,
    height     =>  800,
);

my $STATS-LOCATION = ‘./data/stats’.IO.absolute.IO;
my %OPTIONS = %(
    core         => ‘CORE.setting.moarvm file size (MB)’,
    lines        => ‘Lines in CORE.setting.moarvm file (count)’,
    install      => ‘Space taken by a full installation (MB)’,
    libmoar      => ‘libmoar.so file size (MB)’,
    startup      => ‘startup time (s)’,
    maxrss       => ‘hello world maxrss (MB)’,
);

my %stats;
my %stat-locks;

method help($msg) {
    ‘Available stats: ’ ~ join ‘, ’,
        ‘core (CORE.setting size)’,
        ‘lines (lines in CORE.setting)’,
        ‘install (size of the installation)’,
        ‘libmoar (libmoar.so size)’,
        ‘startup (startup time)’,
        ‘maxrss (maxrss of a hello world)’,
}

sub core-setting-files($path) {
    dir “$path/share/perl6/runtime/”,
        test => /^‘CORE.’[<-[.]>+‘.’]?‘setting.moarvm’$/
}

multi stat-for-commit(‘core’, $full-hash) {
    my $total-size = 0;
    run-smth :!wipe, :!lock, $full-hash, {
        for core-setting-files $_ {
            $total-size += .IO.s if .IO.e
        }
    }
    $total-size ÷ 10⁶
}

multi stat-for-commit(‘lines’, $full-hash) {
    run-smth :!wipe, :!lock, $full-hash, {
        my $moar = “$_/bin/moar”;
        core-setting-files($_).map({
            my %files;
            my $dump = run :out, $moar, ‘--dump’, $_;
            my $grep = run :out, 'grep', ‘annotation: SETTING::’, :in($dump.out);

            for $grep.out.lines {
                # Do not touch this unless you have a good reason to. It does this:
                # my ($file, $line) = .split(‘:’)[3,4];
                # %files{$file} = $line;
                use nqp;
                my $start-file = nqp::index($_, ‘::’) + 2;
                my $start-line = nqp::index($_, ‘:’, $start-file) + 1;
                %files{nqp::substr($_, $start-file, $start-line - $start-file - 1)} = nqp::substr($_, $start-line);
            }
            %files.values.sum
        }).sum
    }
}

multi stat-for-commit(‘install’, $full-hash) {
    run-smth :!wipe, :!lock, $full-hash, {
        # ↓ scary, but works
        Rakudo::Internals.DIR-RECURSE($_).map(*.IO.s).sum ÷ 10⁶
    }
}

multi stat-for-commit(‘libmoar’, $full-hash) {
    run-smth :!wipe, :!lock, $full-hash, {
        my $file = “$_/lib/libmoar.so”.IO;
        $file.IO.s ÷ 10⁶
    }
}

sub snippet-stat($key, $full-hash, $code, :$iterations=5) {
    my $file = write-code $code;
    LEAVE .unlink with $file;
    my $stat = Inf;
    for ^$iterations { # maybe this will make the results more stable?
        my $result = run-snippet :!wipe, :!lock, $full-hash, $file;
        return if $result<exit-code> ≠ 0;
        return if $result<signal>   ≠ 0;
        return if $result<output> ne “42\n” && $key ne ‘output’;
        $stat min= +$result{$key};
    }
    $stat
}

multi stat-for-commit(‘startup’, $full-hash) {
    (snippet-stat  ‘time’, $full-hash, ‘say 42’).Rat # .Rat because +Durations does nothing
}

multi stat-for-commit(‘maxrss’, $full-hash) {
    snippet-stat ‘output’, $full-hash, ‘use Telemetry; print T<max-rss>’
}

#| Generate and fill the stats
sub rakudo-stats($full-hash) {
    my $stats-to-generate = %OPTIONS.keys ∖ $%stats<rakudo>{$full-hash}.keys;
    return if $stats-to-generate == 0;

    return unless build-exists $full-hash;
    my $hello-world = write-code ‘say 42’;
    LEAVE .unlink with $hello-world;
    my $result = run-snippet $full-hash, $hello-world, :!wipe; # leave the build unpacked
    LEAVE { # remove unpacked build
        my $path = run-smth-build-path $full-hash;
        rmtree $path;
    }
    if $result<exit-code> ≠ 0
    or $result<signal>    ≠ 0
    or $result<output> ne “42\n” {
        %stats<rakudo>{$full-hash} = Nil;
        return # exit early if the build is not usable
    }

    for %OPTIONS.keys.sort {
        next if $%stats<rakudo>{$full-hash}{$_}:exists;
        %stats<rakudo>{$full-hash}{$_} = stat-for-commit $_, $full-hash
    }
    return True
}

sub commit-list() {
    my @command = |<git log -z --pretty=%H>, |%*BOT-ENV<range>;
    run(:out, :cwd($CONFIG<projects><rakudo-moar><repo-path>), |@command)
    .out.split(0.chr, :skip-empty).grep({so $_})
}

multi method irc-to-me($msg where /:i ( @(%OPTIONS.keys) ) (‘0’)? /) {
    my $type   = ~$0;
    my $zeroed = ?$1;
    start process $msg, $type, $zeroed
}

sub process($msg, $type, $zeroed) {
    reply $msg, ‘OK! Working on it…’;

    my @results;
    %stat-locks<rakudo>.protect: {
        for commit-list() -> $full {
            @results.push: $full => $_ with %stats<rakudo>{$full}{$type}
        }
    }

    my $pfilename = ‘plot.svg’;
    my $title = %OPTIONS{$type};
    my @values = @results.reverse».value;
    my @labels = @results.reverse».key».substr: 0, 8;

    my $plot = SVG::Plot.new(
        width => %*BOT-ENV<width>,
        height => %*BOT-ENV<height>,
        min-y-axis => $zeroed ?? 0 !! Nil,
        :$title,
        values     => (@values,),
        :@labels,
        background => %*BOT-ENV<background>,
    ).plot(:lines);
    my %graph = $pfilename => SVG.serialize: $plot;

    my $msg-response = @results.reverse.map(*.kv.join: ‘ ’).join: “\n”;

    (‘’ but ProperStr($msg-response)) but FileStore(%graph)
}

multi method keep-reminding($msg) {
    # TODO multi-server setup not supported (this will be irrelevant after #284)
    #sleep 60 × 5; # let other bots start up and stuff
    loop {
        my $available-mem = +run(:out, <free -m>).out.lines\
                            .grep(/‘Mem:’/).words[6];
        my $used-swap     = +run(:out, <free -m>).out.lines\
                            .grep(/‘Swap:’/).words[2];
        my $cpu-avg1min   = +run(:out, ‘uptime’).out.slurp\
                            .match(/‘load average: ’ <( .*$/).split(/<[, ]>+/)[0]; # )>;

        dd $available-mem;
        dd $used-swap;
        dd $cpu-avg1min;
        if $available-mem < 4000 or $used-swap > 50 or $cpu-avg1min > 0.8 {
            sleep 60 × 10; # sleep for now, let's try later
            next
        }
        exit;
        sub save { spurt “$STATS-LOCATION/rakudo”, to-json %stats<rakudo> }

        my $let's-save = False;
        %stat-locks<rakudo>.protect: {
            for commit-list() -> $full {
                next unless rakudo-stats $full;
                last if ++$let's-save %% 10; # save periodically for very long runs
            }
            save if $let's-save;
        }
        next if $let's-save; # no need to sleep, start doing right away
        sleep 60 × 10
    }

    CATCH { default { self.handle-exception: $_, $msg } }
}

multi method irc-connected($msg) {
    once start self.keep-reminding: $msg
}


mkdir $STATS-LOCATION if $STATS-LOCATION.IO !~~ :d;
for (‘rakudo’,) {
    %stat-locks{$_} = Lock.new;
    %stats{$_} = $STATS-LOCATION.add($_).IO.e
          ?? from-json slurp $STATS-LOCATION.add($_)
          !! %()
}

Statisfiable.new.selfrun: ‘statisfiable6’, [ / stat[s]?6? <before ‘:’> /,
                                             fuzzy-nick(‘statisfiable6’, 3) ]

# vim: expandtab shiftwidth=4 ft=perl6

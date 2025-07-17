#!/usr/bin/env perl6
# Copyright © 2016-2017
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

use IRC::Client:ver<4.0.14+>:auth<zef:lizmat>;
use JSON::Fast:ver<0.19+>:auth<cpan:TIMOTIMO>;
use SVG;
use SVG::Plot;

unit class Statisfiable does Whateverable;

%*BOT-ENV = %(
    range      => ‘2014.01..HEAD’,
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
);

my %stats;
my %stat-locks;

method help($msg) {
    ‘Available stats: ’ ~ join ‘, ’,
        ‘core (CORE.setting size)’,
        ‘lines (lines in CORE.setting)’,
        ‘install (size of the installation)’,
        ‘libmoar (libmoar.so size)’
}

multi stat-for-commit(‘core’, $full-hash) {
    run-smth $full-hash, {
        my $file = “$_/share/perl6/runtime/CORE.setting.moarvm”.IO;
        $file.IO.e ?? $file.IO.s ÷ 10⁶ !! Nil
    }
}

multi method stat-for-commit(‘lines’, $full-hash) {
    # TODO
}

multi stat-for-commit(‘install’, $full-hash) {
    run-smth $full-hash, {
        # ↓ scary, but works
        my $result = Rakudo::Internals.DIR-RECURSE($_).map(*.IO.s).sum ÷ 10⁶;
        $result > 10 ?? $result !! Nil
    }
}

multi stat-for-commit(‘libmoar’, $full-hash) {
    run-smth $full-hash, {
        my $file = “$_/lib/libmoar.so”.IO;
        $file.IO.e ?? $file.IO.s ÷ 10⁶ !! Nil
    }
}

multi method irc-to-me($msg where /:i ( @(%OPTIONS.keys) ) (‘0’)? /) {
    my $type   = ~$0;
    my $zeroed = ?$1;
    start process $msg, $type, $zeroed
}

sub process($msg, $type, $zeroed) {
    $msg.reply: ‘OK! Working on it…’;

    my @results;
    %stat-locks{$type}.protect: {
        my %data := %stats{$type};
        my $let's-save = False;
        my @command = |<git log -z --pretty=%H>, |%*BOT-ENV<range>;

        sub save { spurt “$STATS-LOCATION/$type”, to-json %data }

        for run(:out, :cwd($CONFIG<rakudo>), |@command).out.split: 0.chr, :skip-empty -> $full {
            next unless $full;

            if %data{$full}:!exists and build-exists $full {
                %data{$full} = stat-for-commit $type, $full;
                $let's-save++;
                save if $let's-save %% 50; # save periodically for very long runs
            }
            @results.push: $full => $_ with %data{$full}
        }
        save if $let's-save;
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

    $msg-response but FileStore(%graph)
}


mkdir $STATS-LOCATION if $STATS-LOCATION.IO !~~ :d;
for %OPTIONS.keys {
    %stat-locks{$_} = Lock.new;
    %stats{$_} = $STATS-LOCATION.add($_).IO.e
          ?? from-json slurp $STATS-LOCATION.add($_)
          !! %()
}

Statisfiable.new.selfrun: ‘statisfiable6’, [ / stat[s]?6? <before ‘:’> /,
                                             fuzzy-nick(‘statisfiable6’, 3) ]

# vim: expandtab shiftwidth=4 ft=perl6

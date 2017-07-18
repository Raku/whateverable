#!/usr/bin/env perl6
# Copyright © 2016-2017
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
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

use lib ‘.’;
use Misc;
use Whateverable;

use IRC::Client;

use File::Directory::Tree;
use SVG::Plot;
use SVG;
use Stats;

unit class Benchable does Whateverable;

constant TOTAL-TIME = 60 × 4;
constant ITERATIONS = 5;
constant LIB-DIR    = ‘.’.IO.absolute;

method help($msg) {
    ‘Like this: ’ ~ $msg.server.current-nick
    ~ ‘: f583f22,HEAD my $a = ‘a’ x 2¹⁶; for ^1000 {my $b = $a.chop($_)}’
}

multi method benchmark-code($full-commit, $filename) {
    my @times;
    my %stats;
    for ^ITERATIONS {
        my $result = self.run-snippet: $full-commit, $filename;
        if $result<exit-code> ≠ 0 {
            %stats<err> = “«run failed, exit code = $result<exit-code>, exit signal = $result<signal>»”;
            return %stats
        }
        @times.push: sprintf ‘%.4f’, $result<time>
    }

    # TODO min/max/mean/sd are working on stringified numbers? Is that what we want?
    %stats<min>    = min  @times;
    %stats<max>    = max  @times;
    %stats<mean>   = mean @times;
    %stats<stddev> = sd   @times;

    %stats
}

multi method benchmark-code($full-commit-hash, @code) {
    my $code-to-compare = ‘use Bench; my %subs = ’ ~ @code.kv.map({ $^k => “ => sub \{ $^v \} ” }).join(‘,’) ~ ‘;’
                        ~ ‘ my $b = Bench.new; $b.cmpthese(’ ~ ITERATIONS × 2 ~ ‘, %subs)’;

    # lock on the destination directory to make
    # sure that other bots will not get in our way.
    while run(‘mkdir’, ‘--’, “{BUILDS-LOCATION}/rakudo-moar/$full-commit-hash”).exitcode ≠ 0 {
        sleep 0.5;
        # Uh, wait! Does it mean that at the same time we can use only one
        # specific build? Yes, and you will have to wait until another bot
        # deletes the directory so that you can extract it back again…
        # There are some ways to make it work, but don't bother. Instead,
        # we should be doing everything in separate isolated containers (soon),
        # so this problem will fade away.
    }
    my $proc = run :out, :bin, ‘pzstd’, ‘-dqc’, ‘--’, “{ARCHIVES-LOCATION}/rakudo-moar/$full-commit-hash.zst”;
    run :in($proc.out), :bin, ‘tar’, ‘x’, ‘--absolute-names’;
    my $timing;
    if “{BUILDS-LOCATION}/rakudo-moar/$full-commit-hash/bin/perl6”.IO !~~ :e {
        return ‘Commit exists, but a perl6 executable could not be built for it’
    } else {
        $timing = self.get-output(“{BUILDS-LOCATION}/rakudo-moar/$full-commit-hash/bin/perl6”,
                                  ‘--setting=RESTRICTED’, ‘-I’,
                                  “{LIB-DIR}/perl6-bench/lib,{LIB-DIR}/Perl6-Text--Table--Simple/lib”,
                                  ‘-e’, $code-to-compare)<output>
    }
    rmtree “{BUILDS-LOCATION}/rakudo-moar/$full-commit-hash”;
    $timing
}

multi method irc-to-me($msg where .text ~~ /^ \s* $<config>=([:i compare \s]? \S+) \s+ $<code>=.+ /) {
    my ($value, %additional-files) = self.process: $msg, ~$<config>, ~$<code>;
    return without $value;
    return ($value but Reply($msg)) but FileStore(%additional-files)
}

method process($msg, $config, $code is copy) {
    my $start-time = now;
    my $old-dir = $*CWD;
    my ($commits-status, @commits) = self.get-commits: $config;
    return $commits-status unless @commits;

    my ($succeeded, $code-response) = self.process-code: $code, $msg;
    return $code-response unless $succeeded;
    $code = $code-response;

    my $filename = self.write-code: $code;

    my %graph;

    my %times;
    my $actually-tested = 0;

    for @commits -> $commit {
        FIRST my $once = ‘Give me a ping, Vasili. One ping only, please.’;
        # convert to real ids so we can look up the builds
        my $full-commit = self.to-full-commit: $commit;
        my $short-commit = self.get-short-commit: $commit;
        if not defined $full-commit {
            my @options = <HEAD v6.c releases all>;
            %times{$short-commit}<err> = ‘Cannot find this revision’
            ~ “ (did you mean “{self.get-short-commit: self.get-similar: $commit, @options}”?)”
            # TODO why $commit is a match here when using compare?
        } elsif not self.build-exists: $full-commit {
            %times{$short-commit}<err> = ‘No build for this commit’
        } else { # actually run the code
            with $once {
                my $c = +@commits;
                my $s = $c == 1 ?? ‘’ !! ‘s’;
                $msg.reply: “starting to benchmark the $c given commit$s”
            }
            if $config ~~ /:i compare / {
                %times{$short-commit} = self.benchmark-code: $full-commit, $code.split: ‘|||’
            } else {
                %times{$short-commit} = self.benchmark-code: $full-commit, $filename
            }
            $actually-tested++
        }

        if now - $start-time > TOTAL-TIME {
            return “«hit the total time limit of {TOTAL-TIME} seconds»”
        }
    }

    # for these config options, check if there are any large speed differences between two commits and if so,
    # recursively find the commit in the middle until there are either no more large speed differences or no
    # more commits inbetween (i.e., the next commit is the exact one that caused the difference)
    if $actually-tested > 1 and
       ($config ~~ /:i ^ [ releases | v? 6 \.? c | all ] $ / or $config.contains: ‘,’) {
        $msg.reply: ‘benchmarked the given commits, now zooming in on performance differences’;
        sleep 0.05; # to prevent messages from being reordered
        chdir RAKUDO;

Z:      loop (my $x = 0; $x < @commits - 1; $x++) {
            if now - $start-time > TOTAL-TIME {
                return “«hit the total time limit of {TOTAL-TIME} seconds»”
            }

            next unless %times{@commits[$x]}:exists and %times{@commits[$x + 1]}:exists;          # the commits have to have been run at all
            next if %times{@commits[$x]}<err>:exists or %times{@commits[$x + 1]}<err>:exists;     # and without error
            if abs(%times{@commits[$x]}<min> - %times{@commits[$x + 1]}<min>) ≥ %times{@commits[$x]}<min> × 0.1 {
                my $result = self.get-output: ‘git’, ‘rev-list’, ‘--bisect’, ‘--no-merges’, @commits[$x] ~ ‘^..’ ~ @commits[$x + 1];
                my $new-commit = $result<output>;
                if $result<exit-code> == 0 and defined $new-commit and $new-commit ne ‘’ {
                    my $short-commit = self.get-short-commit: $new-commit;
                    if not self.build-exists: $new-commit {
                        %times{$short-commit}<err> = ‘No build for this commit’
                    } elsif %times{$short-commit}:!exists and $short-commit ne @commits[$x] and $short-commit ne @commits[$x + 1] { # actually run the code
                        %times{$short-commit} = self.benchmark-code: $new-commit, $filename;
                        @commits.splice: $x + 1, 0, $short-commit;
                        redo Z
                    }
                }
            }
        }
    }

    @commits .= map: { self.get-short-commit: $_ };

    if @commits ≥ ITERATIONS {
        my $pfilename = ‘plot.svg’;
        my $title = “$config $code”.trans: ｢"｣ => ｢\"｣;
        my @valid-commits = @commits.grep: { %times{$_}<err>:!exists };
        my @values = @valid-commits.map: { %times{$_}<min> };
        my @labels = @valid-commits.map: { “$_ ({ .<mean max stddev>.map({ sprintf “%.2f”, $_ }).join: ‘,’ with %times{$_} })” };

        my $plot = SVG::Plot.new(
            :1000width,
            :800height,
            :0min-y-axis,
            :$title,
            values => (@values,),
            :@labels,
            background => ‘white’,
        ).plot(:lines);

        %graph{$pfilename} = SVG.serialize: $plot
    }

    my $short-str = ‘¦’ ~ @commits.map({ “$_: ” ~ ‘«’ ~ (%times{$_}<err> // %times{$_}<min> // %times{$_}) ~ ‘»’ }).join:  ‘ ¦’;
    my $long-str  = ‘¦’ ~ @commits.map({ “$_: ” ~ ‘«’ ~ (%times{$_}<err> // %times{$_}<min> // %times{$_}) ~ ‘»’ }).join: “\n¦”;

    return $short-str but ProperStr($long-str), %graph;

    LEAVE {
        chdir $old-dir;
        unlink $filename if defined $filename and $filename.chars > 0
    }
}

Benchable.new.selfrun: ‘benchable6’, [ /bench6?/, fuzzy-nick(‘benchable6’, 2) ];

# vim: expandtab shiftwidth=4 ft=perl6

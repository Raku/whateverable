#!/usr/bin/env perl6
# Copyright © 2016
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
use Whateverable;

use IRC::Client;

use SVG;
use SVG::Plot;
use File::Directory::Tree;
use Stats;

unit class Benchable is Whateverable;

constant LIMIT      = 300;
constant TOTAL-TIME = 60*3;
constant ITERATIONS = 5;
constant LIB-DIR    = '.'.IO.absolute;

method help($message) {
    'Like this: ' ~ $message.server.current-nick ~ ': f583f22,HEAD my $a = "a" x 2**16;for ^1000 {my $b = $a.chop($_)}'
}

multi method benchmark-code($full-commit, $filename) {
    my @times;
    my %stats;
    for ^ITERATIONS {
        my ($, $exit, $signal, $time) = self.run-snippet($full-commit, $filename);
        if $exit == 0 {
            @times.push: sprintf('%.4f', $time);
        } else {
            %stats<err> = "«run failed, exit code = $exit, exit signal = $signal»";
            return %stats;
        }
    }

    %stats<min>    = min(@times);
    %stats<max>    = max(@times);
    %stats<mean>   = mean(@times);
    %stats<stddev> = sd(@times);

    return %stats;
}

multi method benchmark-code($full-commit-hash, @code) {
    my $code-to-compare = 'use Bench; my %subs = ' ~ @code.kv.map({ $^k => " => sub \{ $^v \} " }).join(',') ~ ';'
                        ~ ' my $b = Bench.new; $b.cmpthese(' ~ ITERATIONS*2 ~ ', %subs)';

    # lock on the destination directory to make
    # sure that other bots will not get in our way.
    while run(‘mkdir’, ‘--’, “{BUILDS-LOCATION}/$full-commit-hash”).exitcode != 0 {
        sleep 0.5;
        # Uh, wait! Does it mean that at the same time we can use only one
        # specific build? Yes, and you will have to wait until another bot
        # deletes the directory so that you can extract it back again…
        # There are some ways to make it work, but don't bother. Instead,
        # we should be doing everything in separate isolated containers (soon),
        # so this problem will fade away.
    }
    my $proc = run(:out, :bin, ‘zstd’, ‘-dqc’, ‘--’, “{ARCHIVES-LOCATION}/$full-commit-hash.zst”);
    run(:in($proc.out), :bin, ‘tar’, ‘x’, ‘--absolute-names’);
    my $timing;
    if “{BUILDS-LOCATION}/$full-commit-hash/bin/perl6”.IO !~~ :e {
        return ‘Commit exists, but a perl6 executable could not be built for it’;
    } else {
        $timing = self.get-output(“{BUILDS-LOCATION}/$full-commit-hash/bin/perl6”, '--setting=RESTRICTED', '-I', "{LIB-DIR}/perl6-bench/lib,{LIB-DIR}/Perl6-Text--Table--Simple/lib", '-e', $code-to-compare).head;
    }
    rmtree “{BUILDS-LOCATION}/$full-commit-hash”;
    return $timing;
}

multi method irc-to-me($message where { .text !~~ /:i ^ [help|source|url] ‘?’? $ | ^stdin /
                                        # ↑ stupid, I know. See RT #123577
                                        and .text ~~ /^ \s* $<config>=([:i compare \s]? \S+) \s+ $<code>=.+ / }) {
    my ($value, %additional-files) = self.process($message, ~$<config>, ~$<code>);
    return ResponseStr.new(:$value, :$message, :%additional-files);
}

method process($message, $config, $code is copy) {
    my $start-time = now;
    my @commits;
    my $old-dir = $*CWD;

    my $msg-response = '';
    my %graph;

    if $config ~~ / ‘,’ / {
        @commits = $config.split: ‘,’;
    } elsif $config ~~ /^ $<start>=\S+ ‘..’ $<end>=\S+ $/ {
        chdir RAKUDO; # goes back in LEAVE
        if run(‘git’, ‘rev-parse’, ‘--verify’, $<start>).exitcode != 0 {
            return “Bad start, cannot find a commit for “$<start>””;
        }
        if run(‘git’, ‘rev-parse’, ‘--verify’, $<end>).exitcode   != 0 {
            return “Bad end, cannot find a commit for “$<end>””;
        }
        my ($result, $exit-status, $exit-signal, $time) =
          self.get-output(‘git’, ‘rev-list’, “$<start>^..$<end>”); # TODO unfiltered input
        return ‘Couldn't find anything in the range’ if $exit-status != 0;
        @commits = $result.split: “\n”;
        my $num-commits = @commits.elems;
        return “Too many commits ($num-commits) in range, you're only allowed {LIMIT}” if $num-commits > LIMIT;
    } elsif $config ~~ /:i releases / {
        @commits = @.releases;
    } elsif $config ~~ /:i compare \s $<commit>=\S+ / {
        @commits = $<commit>;
    } else {
        @commits = $config;
    }

    my ($succeeded, $code-response) = self.process-code($code, $message);
    return $code-response unless $succeeded;
    $code = $code-response;

    my $filename = self.write-code($code);

    $message.reply: "starting to benchmark the {+@commits} given commits";
    my %times;
    for @commits -> $commit {
        # convert to real ids so we can look up the builds
        my $full-commit = self.to-full-commit($commit);
        my $short-commit = self.get-short-commit($commit);
        if not defined $full-commit {
            %times{$short-commit}<err> = ‘Cannot find this revision’;
        } elsif not self.build-exists($full-commit) {
            %times{$short-commit}<err> = ‘No build for this commit’;
        } else { # actually run the code
            if $config ~~ /:i compare / {
                %times{$short-commit} = self.benchmark-code($full-commit, $code.split('|||'));
            } else {
                %times{$short-commit} = self.benchmark-code($full-commit, $filename);
            }
        }

        if (now - $start-time > TOTAL-TIME) {
            return "«hit the total time limit of {TOTAL-TIME} seconds»";
        }
    }

    # for these two config options, check if there are any large speed differences between two commits and if so, 
    # recursively find the commit in the middle until there are either no more large speed differences or no
    # more commits inbetween (i.e., the next commit is the exact one that caused the difference)
    if $config ~~ /:i releases / or $config ~~ / ',' / {
        $message.reply: 'benchmarked the given commits, now zooming in on performance differences';
        chdir RAKUDO;

Z:      loop (my int $x = 0; $x < @commits - 1; $x++) {
            if (now - $start-time > TOTAL-TIME) {
                return "«hit the total time limit of {TOTAL-TIME} seconds»";
            }

            next unless %times{@commits[$x]}:exists and %times{@commits[$x + 1]}:exists;          # the commits have to have been run at all
            next if %times{@commits[$x]}<err>:exists or %times{@commits[$x + 1]}<err>:exists;     # and without error
            if abs(%times{@commits[$x]}<min> - %times{@commits[$x + 1]}<min>) >= %times{@commits[$x]}<min>*0.1 {
                my ($new-commit, $exit-status, $exit-signal, $time) = self.get-output('git', 'rev-list', '--bisect', '--no-merges', @commits[$x] ~ '^..' ~ @commits[$x + 1]);
                if $exit-status == 0 and $new-commit.defined and $new-commit ne '' {
                    my $short-commit = self.get-short-commit($new-commit);
                    if not self.build-exists($new-commit) {
                        %times{$short-commit}<err> = ‘No build for this commit’;
                    } elsif %times{$short-commit}:!exists and $short-commit ne @commits[$x] and $short-commit ne @commits[$x + 1] { # actually run the code
                        %times{$short-commit} = self.benchmark-code($new-commit, $filename);
                        @commits.splice($x + 1, 0, $short-commit);
                        redo Z;
                    }
                }
            }
        }
    }

    @commits .= map({ self.get-short-commit($_) });

    if @commits >= ITERATIONS {
        my $pfilename = 'plot.svg';
        my $title = "$config $code".trans(['"'] => ['\"']);
        my @valid-commits = @commits.grep({ %times{$_}<err>:!exists });
        my @values = @valid-commits.map({ %times{$_}<min> });
        my @labels = @valid-commits.map({ "$_ ({ .<mean max stddev>.map({ sprintf("%.2f", $_) }).join(',') with %times{$_} })" });

        my $plot = SVG::Plot.new(
            width      => 1000,
            height     => 800,
            min-y-axis => 0,
            :$title,
            values     => (@values,),
            :@labels,
            background => 'white',
        ).plot(:lines);

        %graph{$pfilename} = SVG.serialize($plot);
    }

    $msg-response ~= '¦' ~ @commits.map({ "«$_»:" ~(%times{$_}<err> // %times{$_}<min> // %times{$_}) }).join("\n¦");

    return ($msg-response, %graph);

    LEAVE {
        chdir $old-dir;
        unlink $filename if $filename.defined and $filename.chars > 0;
    }
}

Benchable.new.selfrun(‘benchable6’, [‘bench’, ‘bench6’]);

# vim: expandtab shiftwidth=4 ft=perl6

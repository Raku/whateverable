#!/usr/bin/env perl
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

use Stats;
use Chart::Gnuplot:from<Perl5>;
use Chart::Gnuplot::DataSet:from<Perl5>;

unit class Benchable is Whateverable;

constant LIMIT      = 300;
constant TOTAL-TIME = 60*3;
constant ITERATIONS = 5;

method help($message) {
    'Like this: ' ~ $message.server.current-nick ~ ': f583f22,HEAD my $a = "a" x 2**16;for ^1000 {my $b = $a.chop($_)}'
}

method benchmark-code($full-commit, $filename) {
    my @times;
    my %stats;
    for ^ITERATIONS {
        my ($, $exit, $signal, $time) = self.get-output("{BUILDS}/$full-commit/bin/perl6", $filename);
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

multi method irc-to-me($message where .text ~~ /^ \s* $<config>=\S+ \s+ $<code>=.+ /) {
    my ($value, %additional-files) = self.process($message, ~$<config>, ~$<code>);
    return ResponseStr.new(:$value, :$message, :%additional-files);
}

method process($message, $config, $code is copy) {
    my $start-time = now;

    my $msg-response = '';
    my %graph;

    my @commits;
    if $config ~~ / ',' / {
        @commits = $config.split: ',';
    } elsif $config ~~ /^ $<start>=\S+ \.\. $<end>=\S+ $/ {
        my $old-dir = $*CWD;
        chdir RAKUDO;
        LEAVE chdir $old-dir;
        return "Bad start" if run('git', 'rev-parse', '--verify', $<start>).exitcode != 0;
        return "Bad end"   if run('git', 'rev-parse', '--verify', $<end>).exitcode   != 0;

        my ($result, $exit-status, $exit-signal, $time) = self.get-output('git', 'rev-list', "$<start>^..$<end>");

        return "Couldn't find anything in the range" if $exit-status != 0;

        @commits = $result.split: "\n";
        my $num-commits = @commits.elems;
        return "Too many commits ($num-commits) in range, you're only allowed " ~ LIMIT if $num-commits > LIMIT;
    } elsif $config ~~ /:i releases / {
        @commits = <2015.10 2015.11 2015.12 2016.02 2016.03 2016.04 2016.05 2016.06 2016.07 HEAD>;
    } else {
        @commits = $config;
    }

    my ($succeeded, $code-response) = self.process-code($code, $message);
    return $code-response unless $succeeded;
    $code = $code-response;

    my $filename = self.write-code($code);

    my %times;
    for @commits -> $commit {
        # convert to real ids so we can look up the builds
        my $full-commit = self.to-full-commit($commit);
        my $short-commit = $commit.substr(0, 7);
        if !$full-commit.defined {
            %times{$short-commit}<err> = 'Cannot find this revision';
        } elsif “{BUILDS}/$full-commit/bin/perl6”.IO !~~ :e {
            %times{$short-commit}<err> = 'No build for this commit';
        } else { # actually run the code
            %times{$short-commit} = self.benchmark-code($full-commit, $filename);
        }

        if (now - $start-time > TOTAL-TIME) {
            return "«hit the total time limit of {TOTAL-TIME} seconds»";
        }
    }

    # for these two config options, check if there are any large speed differences between two commits and if so, 
    # recursively find the commit in the middle until there are either no more large speed differences or no
    # more commits inbetween (i.e., the next commit is the exact one that caused the difference)
    if $config ~~ /:i releases / or $config ~~ / ',' / {
        my $old-dir = $*CWD;
        chdir RAKUDO;
        LEAVE chdir $old-dir;

Z:      loop (my int $x = 0; $x < +@commits - 1; $x++) {
            if (now - $start-time > TOTAL-TIME) {
                return "«hit the total time limit of {TOTAL-TIME} seconds»";
            }

            next unless %times{@commits[$x]}:exists and %times{@commits[$x + 1]}:exists;          # the commits have to have been run at all
            next if %times{@commits[$x]}<err>:exists or %times{@commits[$x + 1]}<err>:exists;     # and without error
            if abs(%times{@commits[$x]}<min> - %times{@commits[$x + 1]}<min>) >= %times{@commits[$x]}<min>*0.1 {
                my ($new-commit, $exit-status, $exit-signal, $time) = self.get-output('git', 'rev-list', '--bisect', '--no-merges', @commits[$x] ~ '^..' ~ @commits[$x + 1]);
                if $exit-status == 0 and $new-commit.defined  and $new-commit ne '' {
                    my $short-commit = $new-commit.substr(0, 7);
                    if "{BUILDS}/$new-commit/bin/perl6".IO !~~ :e {
                        %times{$short-commit}<err> = 'No build for this commit';
                    } elsif %times{$short-commit}:!exists and $short-commit ne @commits[$x] and $short-commit ne @commits[$x + 1] { # actually run the code
                        %times{$short-commit} = self.benchmark-code($new-commit, $filename);
                        @commits.splice($x + 1, 0, $short-commit);
                        redo Z;
                    }
                }
            }
        }
    }

    if @commits >= ITERATIONS {
        my $gfilename = 'graph.svg';
        my $title = "$config $code".trans(['"'] => ['\"']);
        my @ydata = @commits.map({ .<err> // .<min> with %times{$_.substr(0, 7)} });
        my $chart = Chart::Gnuplot.new(
            output   => $gfilename,
            encoding => 'utf8',
            title	 => {
                text     => $title.encode('UTF-8'),
                enhanced => 'off',
            },
            size     => '2,1',
#        terminal => 'svg mousing',
            xlabel   => {
                text   => 'Commits\\nMean,Max,Stddev',
                offset => '0,-1',
            },
            xtics    => { labels => [@commits.kv.map({ my $commit = $^v.substr(0, 7); "\"$commit\\n{.<err> // .<mean max stddev>.join(',') with %times{$commit}}\" $^k" })], },
            ylabel   => 'Seconds',
            yrange   => [0, @ydata.grep(*.Num).max * 1.25],
          );
        my $dataSet = Chart::Gnuplot::DataSet.new(
            ydata => item(@ydata),
            style => 'linespoints',
          );
        $chart.plot2d($dataSet);

        %graph{$gfilename} = $gfilename.IO.slurp;
    }

    $msg-response ~= '¦' ~ @commits.map({ my $c = .substr(0, 7); "«$c»:" ~ (%times{$c}<err> // %times{$c}<min>) }).join("\n¦");

    return ($msg-response, %graph);
}

Benchable.new.selfrun(‘benchable6’);

# vim: expandtab shiftwidth=4 ft=perl6

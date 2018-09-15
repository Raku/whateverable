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
use Whateverable::Output;
use Whateverable::Running;

use IRC::Client;

unit class Bloatable does Whateverable;

method help($msg) {
    “Like this: {$msg.server.current-nick}: d=compileunits 292dc6a,HEAD”
}

multi method irc-to-me($msg where /^ :r [ [ ‘d=’ | ‘-d’ \s* ] $<sources>=[\S+] \s ]?
                                    \s* $<config>=<.&commit-list> $/) {
    self.process: $msg, ~$<config>, ~($<sources> // ‘compileunits’)
}

multi method bloaty($sources, %prev, %cur) {
    run-smth :backend<moarvm>, %prev<full-commit>, -> $prev-path {
        !“$prev-path/lib/libmoar.so”.IO.e
        ?? “No libmoar.so file in build %prev<short-commit>”
        !! run-smth :backend<moarvm>, %cur<full-commit>, -> $cur-path {
            !“$cur-path/lib/libmoar.so”.IO.e
            ?? “No libmoar.so file in build %cur<short-commit>”
            !! get-output ‘bloaty’, ‘-d’, $sources, ‘-n’, ‘50’,
                          “$cur-path/lib/libmoar.so”, ‘--’, “$prev-path/lib/libmoar.so”
        }
    }
}

multi method bloaty($sources, %prev) {
    run-smth :backend<moarvm>, %prev<full-commit>, -> $prev-path {
        !“$prev-path/lib/libmoar.so”.IO.e
        ?? “No libmoar.so file in build %prev<short-commit>”
        !! get-output ‘bloaty’, ‘-d’, $sources, ‘-n’, ‘100’,
                      “$prev-path/lib/libmoar.so”
    }
}

method did-you-mean($out) {
    return if $out !~~ Associative;
    return if $out<exit-code> == 0;
    return unless $out<output> ~~ /(‘no such data source:’ .*)/;
    $0.tc ~ ‘ (Did you mean one of these: ’
          ~ get-output(‘bloaty’, ‘--list-sources’
                       )<output>.lines.map(*.words[0]).join(‘ ’)
          ~ ‘ ?)’
}

method process($msg, $config, $sources is copy) {
    my @commits = get-commits $config, repo => $CONFIG<moarvm>;
    my %files;
    my @processed;
    for @commits -> $commit {
        my %prev = @processed.tail if @processed;
        my %cur;
        # convert to real ids so we can look up the builds
        %cur<full-commit> = to-full-commit $commit, repo => $CONFIG<moarvm>;
        if not defined %cur<full-commit> {
            %cur<error> = “Cannot find revision $commit”;
            my @options = <HEAD v6.c releases all>;
            %cur<error> ~= “ (did you mean “{get-short-commit get-similar $commit, @options, repo => $CONFIG<moarvm>}”?)”
        } elsif not build-exists %cur<full-commit>, :backend<moarvm> {
            %cur<error> = ‘No build for this commit’
        }
        %cur<short-commit> = get-short-commit $commit;
        %cur<short-commit> ~= “({get-short-commit %cur<full-commit>})” if $commit eq ‘HEAD’;
        if %prev {
            my $filename = “result-{(1 + %files).fmt: ‘%05d’}”;
            my $result = “Comparing %prev<short-commit> → %cur<short-commit>\n”;
            if %prev<error> {
                $result ~= “Skipping because of the error with %prev<short-commit>:\n”;
                $result ~= %prev<error>
            } elsif %cur<error> {
                $result ~= “Skipping because of the error with %cur<short-commit>:\n”;
                $result ~= %cur<error>
            } elsif %prev<full-commit> eq %cur<full-commit> {
                $result ~= “Skipping because diffing the same commit is pointless.”;
            } else {
                my $out = self.bloaty: $sources, %prev, %cur;
                grumble $_ with self.did-you-mean: $out;
                $result ~= $out<output> // $out;
            }
            %files{$filename} = $result
        }
        @processed.push: %cur
    }

    if @commits == 1 {
        my %prev = @processed.tail;
        return %prev<error> if %prev<error>;
        my $out = self.bloaty: $sources, %prev;
        return $_ with self.did-you-mean: $out;
        return ($out<output> // $out) but ProperStr(“%prev<short-commit>\n{$out<output> // $out}”)
    } elsif @commits == 2 and (@processed[*-2]<error> or @processed[*-1]<error>) {
        # print obvious problems without gisting the whole thing
        return @processed[*-2]<error> || @processed[*-1]<error>;
        # TODO this does not catch missing libmoar.so files
    }
    ‘’ but FileStore(%files);
}


my %*BOT-ENV;

Bloatable.new.selfrun: ‘bloatable6’, [ / bloat[y]?6? <before ‘:’> /,
                                       fuzzy-nick(‘bloatable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

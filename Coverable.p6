#!/usr/bin/env perl6
# Copyright © 2016-2017
#     Daniel Green <ddgreen@gmail.com>
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
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

unit class Coverable does Whateverable;

constant TOTAL-TIME = 60 × 3;

sub condense(@list) {
    Seq.new( class :: does Iterator {
        has $.iterator;
        has $!first;
        has $!last;
        method pull-one() {
            if $!iterator {
                if (my $pulled := $!iterator.pull-one) =:= IterationEnd {
                    $!iterator = Nil;
                    $!first.defined
                      ?? $!first == $!last
                        ?? $!last
                        !! Range.new($!first,$!last)
                      !!  IterationEnd
                }
                elsif $pulled ~~ Int:D {
                    if $!first.defined {
                        if $pulled == $!last + 1 {
                            ++$!last;
                            ++$!last
                              while !(($pulled := $!iterator.pull-one) =:= IterationEnd)
                                && $pulled ~~ Int:D
                                && $pulled == $!last + 1;
                        }
                        if $pulled =:= IterationEnd || $pulled ~~ Int:D {
                            my $value = $!first == $!last
                              ?? $!last
                              !! Range.new($!first,$!last);
                            $pulled =:= IterationEnd
                              ?? ($!iterator = Nil)
                              !! ($!first = $!last = $pulled);
                            $value
                        }
                        else {
                            die “Cannot handle $pulled.perl()”
                        }
                    }
                    else {
                        $!first = $!last = $pulled;
                        self.pull-one
                    }
                }
                else {
                    die “Cannot handle $pulled.perl()”
                }
            }
            else {
                IterationEnd
            }
        }
        method is-lazy() { $!iterator.is-lazy }
    }.new(iterator => @list.iterator))
}

method help($msg) {
    “Like this: {$msg.server.current-nick}: f583f22 grep=SETTING:: say ‘hello’; say ‘world’”
}

multi method irc-to-me($msg where { .text ~~ /^ \s* $<config>=<.&commit-list> \s+ [‘grep=’ $<grep>=\S+ \s+]? $<code>=.+ / }) {
    self.process: $msg, ~$<config>, ~($<grep> // ‘SETTING::’), ~$<code>
}

method process($msg, $config is copy, $grep is copy, $code is copy) {
    my $start-time = now;

    if $config ~~ /^ [say|sub] $/ {
        $msg.reply: “Seems like you forgot to specify a revision (will use “HEAD” instead of “$config”)”;
        $code = “$config $code”;
        $config = ‘HEAD’
    }

    my @commits = self.get-commits: $config;
    grumble ‘Coverable only works with one commit’ if @commits > 1;
    $code = self.process-code: $code, $msg;

    my $filename = self.write-code: $code;
    LEAVE { unlink $_ with $filename }

    my $result;
    my %lookup;
    my $output = ‘’;
    my $commit = @commits[0];

    # convert to real ids so we can look up the builds
    my $full-commit = self.to-full-commit: $commit;
    if not defined $full-commit {
        $output = ‘Cannot find this revision’;
        my @options = <HEAD>;
        $output ~= “ (did you mean “{self.get-short-commit: self.get-similar: $commit, @options}”?)”
    } elsif not self.build-exists: $full-commit {
        $output = ‘No build for this commit’
    } else { # actually run the code
        my $log = “coverage_{now.to-posix[0]}.log”;
        LEAVE { unlink $log }

        %*ENV<MVM_COVERAGE_LOG> = $log;
        $result = self.run-snippet: $full-commit, $filename;
        %*ENV<MVM_COVERAGE_LOG>:delete;

        my $g = run ‘grep’, ‘-P’, ‘--’, $grep, $log, :out;
        my $s = run ‘sort’, ‘--key=2,2’, ‘--key=3n’, ‘-u’, :in($g.out), :out;
        my $colrm = run ‘colrm’, 1, 5, :in($s.out), :out;
        $result<coverage> = $colrm.out.slurp-rest.chomp;
        $output = $result<output>;
        if $result<signal> < 0 { # numbers less than zero indicate other weird failures
            $output = “Cannot test this commit ($output)”
        } else {
            $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
            $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0
        }
    }
    my $short-commit = self.get-short-commit: $commit;
    $short-commit ~= “({self.get-short-commit: $full-commit})” if $commit eq ‘HEAD’;

    if now - $start-time > TOTAL-TIME {
        grumble “«hit the total time limit of {TOTAL-TIME} seconds»”
    }

    my $short-str = “¦$short-commit: «$output»”; # TODO no need for short string (we gist it anyway)
    my $long-str  = “¦$full-commit: «$output»”; # TODO simpler output perhaps?

    my %coverage;
    for $result<coverage>.split(“\n”) -> $line {
        my ($filename, $lineno) = $line.split: /\s+/;
        %coverage{$filename}.push: +$lineno;
    }

    my $cover-report = “| File | Code |\n|--|--|\n”;
    my $url = “https://github.com/rakudo/rakudo/blob/$full-commit”;
    # ↓ TODO So we are using RAKUDO, but RAKUDO may not know about some commits *yet*, while
    #        they may be accessible if you give a hash directly.
    my @git  = ‘git’, ‘--git-dir’, “{RAKUDO}/.git”, ‘--work-tree’, RAKUDO;
    for %coverage.keys.sort -> $fn {
        for condense(%coverage{$fn}) -> $l {
            my $ln = ‘L’ ~ ($l ~~ Int ?? $l !! “$l.min()-L$l.max()”);
            if $fn.starts-with(‘SETTING::’) or $fn ~~ m|‘/Perl6/’| {
                my $fname = $fn;
                $fname .= substr(9) if $fn.starts-with(‘SETTING::’);
                $cover-report ~= “| [$fname#$ln]($url/$fname#$ln) |”;
                my $sed-range = “{$l.min},{$l.max}p”;
                # ⚠ TODO don't do this ↓ for every line, do it for every *file*. It will be much faster.
                my $proc = run :out, |@git, ‘show’, “$full-commit:$fname”;
                my $code = run(:out, :in($proc.out), ‘sed’, ‘-n’, $sed-range).out.slurp-rest.trim; # TODO trim? or just chomp?
                $code .= subst(:g, “\n”, ‘```<br>```’); # TODO multiline code blocks using github markdown?
                $code .= subst(:g, ‘|’, ‘\|’); # TODO really?
                $cover-report ~= “ ```$code``` |\n”; # TODO close properly (see how many ``` are there already)
            } else {
                $cover-report ~= “| $fn#$ln | |\n”; # TODO write “N/A” instead of having an empty cell?
            }
        }
    }

    # TODO no need for $short-str as mentioned earlier
    ($short-str but ProperStr($long-str)) but FileStore(%(‘result.md’ => $cover-report));
}

Coverable.new.selfrun: ‘coverable6’, [ / cover6? <before ‘:’> /,
                                       fuzzy-nick(‘coverable6’, 3) ];

# vim: expandtab shiftwidth=4 ft=perl6

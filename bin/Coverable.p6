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

use Whateverable;
use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Config;
use Whateverable::Processing;
use Whateverable::Running;

use IRC::Client;

unit class Coverable does Whateverable;

constant TOTAL-TIME = 60 × 3;

method help($msg) {
    “Like this: {$msg.server.current-nick}: f583f22 grep=SETTING:: say ‘hello’; say ‘world’”
}

multi method irc-to-me($msg where /^ \s* $<config>=<.&commit-list> \s+ [‘grep=’ $<grep>=\S+ \s+]? $<code>=.+ /) {
    self.process: $msg, ~$<config>, ~($<grep> // ‘SETTING::’), ~$<code>
}

sub condense(@arr) { # squish into ranges
    my $cur = False;
    gather for @arr {
        if $_ - 1 ~~ $cur {
            $cur = $cur.min .. $_
        } else {
            take $cur if $cur !== False;
            $cur = $_
        }
        LAST take $cur
    }
}

method process($msg, $config is copy, $grep is copy, $code) {
    my $start-time = now;

    if $config ~~ /^ [say|sub] $/ {
        $msg.reply: “Seems like you forgot to specify a revision (will use “HEAD” instead of “$config”)”;
        $code = “$config $code”;
        $config = ‘HEAD’
    }

    my @commits = get-commits $config;
    grumble ‘Coverable only works with one commit’ if @commits > 1;

    my $file = process-code $code, $msg;
    LEAVE .unlink with $file;

    my $result;
    my %lookup;
    my $output = ‘’;
    my $commit = @commits[0];

    # convert to real ids so we can look up the builds
    my $full-commit = to-full-commit $commit;
    if not defined $full-commit {
        $output = ‘Cannot find this revision’;
        my @options = <HEAD>;
        $output ~= “ (did you mean “{get-short-commit get-similar $commit, @options}”?)”
    } elsif not build-exists $full-commit {
        $output = ‘No build for this commit’
    } else { # actually run the code
        my $log = $*TMPDIR.add: “coverage_{now.to-posix[0]}.log”; # TODO proper temp file name
        LEAVE { unlink $log }

        %*ENV<MVM_COVERAGE_LOG> = $log;
        $result = run-snippet $full-commit, $file;
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
    my $short-commit = get-short-commit $commit;
    $short-commit ~= “({get-short-commit $full-commit})” if $commit eq ‘HEAD’;

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
    for %coverage.keys.sort -> $fn {
        for condense %coverage{$fn} -> $l {
            my $ln = ‘L’ ~ ($l ~~ Int ?? $l !! “$l.min()-L$l.max()”);
            if $fn.starts-with(‘SETTING::’) or $fn ~~ m|‘/Perl6/’| {
                my $fname = $fn;
                $fname .= substr(9) if $fn.starts-with(‘SETTING::’);
                $cover-report ~= “| [$fname#$ln]($url/$fname#$ln) |”;
                my $sed-range = “{$l.min},{$l.max}p”;
                # ⚠ TODO don't do this ↓ for every line, do it for every *file*. It will be much faster.
                my $proc = run :out, :cwd($CONFIG<rakudo>), <git show>, “$full-commit:$fname”;
                # TODO So we are using RAKUDO ↑, but RAKUDO may not know about some commits *yet*, while
                #      they may be accessible if you give a hash directly.
                my $code = run(:out, :in($proc.out), <sed -n>, $sed-range).out.slurp-rest.trim; # TODO trim? or just chomp?
                $code .= subst: :g, “\n”, ‘```<br>```’; # TODO multiline code blocks using github markdown?
                $code .= subst: :g, ‘|’, ‘\|’; # TODO really?
                $cover-report ~= “ ```$code``` |\n”; # TODO close properly (see how many ``` are there already)
            } else {
                $cover-report ~= “| $fn#$ln | |\n”; # TODO write “N/A” instead of having an empty cell?
            }
        }
    }

    # TODO no need for $short-str as mentioned earlier
    ($short-str but ProperStr($long-str)) but FileStore(%(‘result.md’ => $cover-report));
}


my %*BOT-ENV;

Coverable.new.selfrun: ‘coverable6’, [ / cover6? <before ‘:’> /,
                                       fuzzy-nick(‘coverable6’, 3) ];

# vim: expandtab shiftwidth=4 ft=perl6

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

use Misc;
use Whateverable;

use IRC::Client;
use Config::INI;

unit class Greppable does Whateverable;

my \ECO-PATH = ‘data/all-modules’;

method help($msg) {
    “Like this: {$msg.server.current-nick}: password”
}
sub process-line($line, %commits) { # 🙈
    my $backticks = ｢`｣ x (($line.comb(/｢`｣+/) || ｢｣).max.chars + 1);
    my ($path, $line-number, $text) = $line.split: “\x0”, 3;

    my $start = $path; # Not a module, unless…
    if $path ~~ /^ $<repo>=[ <-[/]>+ ‘/’ <-[/]>+ ] ‘/’ $<path>=.* $/ {
        my $repo      = $<repo>;
        my $long-path = $<path>;
        my $commit    = %commits{$repo};
        without $commit { # cache it!
            $commit = Config::INI::parse(slurp “{ECO-PATH}/$repo/.gitrepo”)<subrepo><commit>;
            %commits{$repo} = $commit;
        }
        my $link = “https://github.com/$repo/blob/$commit/$long-path#L$line-number”;
        my $short-path = $long-path.subst: /^ .*‘/’ /, ‘’;
        $short-path = “…/$short-path”;# if $long-path ne $short-path;
        $start = “[{$repo}<br>``{$short-path}`` :*$line-number*:]($link)”
    }
    $text = shorten $text, 300; # do not print too long lines
    $text = markdown-escape $text;
    $text ~~ s:g/ “\c[ESC][1;31m” (.*?) [ “\c[ESC][m” | $ ] /<b>{$0}<\/b>/; # TODO get rid of \/ ?

    “| $start | <code>{$text}</code> |”
}

multi method irc-to-me($msg) {
    run :out(Nil), :cwd(ECO-PATH), ‘git’, ‘pull’;
    my $result = get-output :cwd(ECO-PATH), ‘git’, ‘grep’,
                                            ‘--color=always’, ‘-z’, ‘-i’, ‘-I’,
                                            ‘--perl-regexp’, ‘--line-number’,
                                            ‘--’, $msg;

    grumble ‘Sorry, can't do that’ if $result<exit-code> ≠ 0 | 1 or $result<signal> ≠ 0;
    grumble ‘Found nothing!’ unless $result<output>;
    my %commits = ();
    my $gist = “| File | Code |\n|--|--|\n”
             ~ $result<output>.lines.map({process-line $_, %commits}).join: “\n”;
    ‘’ but FileStore({ ‘result.md’ => $gist})
}


if ECO-PATH.IO !~~ :d {
    run ‘git’, ‘clone’, ‘https://github.com/moritz/perl6-all-modules.git’, ECO-PATH
}

Greppable.new.selfrun: ‘greppable6’, [ / grep6? <before ‘:’> /,
                                       fuzzy-nick(‘greppable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

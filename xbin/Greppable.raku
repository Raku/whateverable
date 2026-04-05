#!/usr/bin/env raku
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
use Whateverable::Output;
use Whateverable::Running;

use Config::INI;
use IRC::Client;

unit class Greppable does Whateverable;

my $ECO-PATH   = ‘data/all-modules’;
my $ECO-ORIGIN = ‘https://github.com/moritz/perl6-all-modules’;

method help($msg) {
    “Like this: {$msg.server.current-nick}: password”
}

sub process-ls-line($line) {
    # TODO markdownify
    $line
}
sub process-grep-line($line, %commits) { # 🙈
    my $backticks = ｢`｣ x (($line.comb(/｢`｣+/) || ｢｣).max.chars + 1);
    my ($path, $line-number, $text) = $line.split: “\x0”, 3;

    return Empty if $path.ends-with: ‘.pdf’; # somehow pdf files are not considered binary

    my $start = “perl6-all-modules/$path”; # Not a module, unless…
    if $path ~~ /^ $<source>=[<-[/]>+] ‘/’ $<repo>=[ <-[/]>+ ‘/’ <-[/]>+ ]
                                       ‘/’ $<path>=.* $/ {
        my $source    = $<source>;
        my $repo      = $<repo>;
        my $long-path = $<path>;
        my $commit    = %commits{“$source/$repo”};

        without $commit { # cache it!
            $commit = do given $source {
                my $dotgitrepo = “$ECO-PATH/$source/$repo/.gitrepo”.IO;
                when ‘github’
                   | ‘gitlab’ { Config::INI::parse(slurp $dotgitrepo)<subrepo><commit> }
                when ‘cpan’   { run(:out, :cwd($ECO-PATH),
                                    <git rev-parse HEAD>).out.slurp.trim }
                default       { die “Unsupported source “$source”” }
            }
            %commits{$repo} = $commit;
        }
        my $link = do given $source {
            when ‘github’
               | ‘gitlab’ { “https://$source.com/$repo/blob/$commit/$long-path#L$line-number” }
            when ‘cpan’   { “$ECO-ORIGIN/blob/$commit/$source/$repo/$long-path#L$line-number” }
            default       { die “Unsupported source “$source”” } # already handled anyway
        }
        my $short-path = $long-path.subst: /^ .*‘/’ /, ‘’;
        $short-path = “…/$short-path”;# if $long-path ne $short-path;
        $start = “[{$repo}<br>``{$short-path}`` :*$line-number*:]($link)”;

        take ~$repo # used for stats in PrettyLink
    }
    $text = shorten $text || ‘’, 300; # do not print too long lines
    $text = markdown-escape $text;
    $text ~~ s:g/ “\c[ESC][1;31m” (.*?) [ “\c[ESC][m” | $ ] /<b>{$0}<\/b>/; # TODO get rid of \/ ?

    “| $start | <code>{$text}</code> |”
}

multi method irc-to-me($msg where .args[1].starts-with(‘file’ | ‘tree’) &&
                                  /^ \s* [ || ‘/’ $<regex>=[.*] ‘/’
                                           || $<regex>=[.*?]       ] \s* $/) {
    my $result = run :out, :cwd($ECO-PATH), <git ls-files -z>;
    my $out = perl6-grep $result.out, $<regex>;
    my $gist = $out.map({ process-ls-line $_ }).join(“\n”);
    return ‘Found nothing!’ unless $gist;
    ‘’ but ProperStr($gist)
}

multi method irc-to-me($msg) {
    my @cmd = |<git grep --color=always -z -I
              --perl-regexp --line-number -->, $msg;

    run :out(Nil), :cwd($ECO-PATH), <git pull>;
    my $result = get-output :cwd($ECO-PATH), |@cmd;

    grumble ‘Sorry, can't do that’ if $result<exit-code> ≠ 0 | 1 or $result<signal> ≠ 0;
    grumble ‘Found nothing!’ unless $result<output>;

    my %commits = ();
    my $gist = “| File | Code |\n|--|--|\n”;
    my $stats = gather {
        $gist ~= $result<output>.split(/“\n”|“\r\n”/).map({process-grep-line $_, %commits}).join: “\n”;
        # 🙈 after touching the .split part three times, I think this should work…
        # 🙈 it will eat \r but that's not too bad
    }
    my $total   = $stats.elems;
    my $modules = $stats.Set.elems;
    (‘’ but FileStore({ ‘result.md’ => $gist }))
    but PrettyLink({“{s $total, ‘line’}, {s $modules, ‘module’}: $_”})
}


if $ECO-PATH.IO !~~ :d {
    run <git clone>, $ECO-ORIGIN, $ECO-PATH
}

Greppable.new.selfrun: ‘greppable6’, [ / [file|tree]? grep6? <before ‘:’> /,
                                       fuzzy-nick(‘greppable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

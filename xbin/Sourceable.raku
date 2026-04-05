#!/usr/bin/env perl6
# Copyright © 2019-2023
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
# Copyright © 2019
#     Alexander Kiryuhin <alexander.kiryuhin@gmail.com>
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
use Whateverable::Output;
use Whateverable::Running;

unit class Sourceable does Whateverable;

my $BLOB-URL = ‘https://github.com/rakudo/rakudo/blob’;

method help($msg) {
    “Like this: {$msg.server.current-nick}: 42.base(16)”
}

multi method irc-to-me($msg where { .Str ~~ m:r/^ [$<maybe-rev>=\S+ \s+]? $<maybe-code>=[.+] $/ }) {
    my $full-commit = to-full-commit $<maybe-rev> // ‘’;
    my $code = ~$<maybe-code>;
    if not $full-commit {
        $full-commit = to-full-commit ‘HEAD’;
        $code = ~$/;
    }
    my $short-commit = get-short-commit $full-commit;
    grumble “No build for revision “$short-commit”” unless build-exists $full-commit;

    # Leave the build unpacked
    my $build-unpacked =
            run-smth $full-commit, {True}, :!wipe, :lock;
    LEAVE { run-smth $full-commit, {;   }, :wipe, :!lock with $build-unpacked }

    my @wild-guesses = gather {
        take $code; # code object (as-is)
        take ‘&’ ~ $code; # sub
        # method
        for $code ~~ m:ex/^ (.+) ‘.’ (.+) $/ -> $/ {
            take “{$0}.^can(‘$1’)[0]”
        }
        # sub with args
        for $code ~~ m:ex/^ (.+) [ \s+ (.*) | ‘(’ (.*) ‘)’ ] $/ -> $/ {
            take ｢&%s.cando(\(%s))[0]｣.sprintf: $0, $1 // $2
        }
        # method with args
        for $code ~~ m:ex/^ (.+) ‘.’ (<[\w-]>+) [ [‘: ’ (.*)] | [‘(’ (.*) ‘)’]? ] $/ -> $/ {
            take ｢(%s).^can(‘%s’).map(*.cando(\((%s), |\(%s)))).first(*.so)[0]｣.sprintf: $0, $1, $0, $2 // $3 // ‘’
        }
        # infix operators
        for $code ~~ m:ex/^ (.+) \s+ (\S+) \s+ (.+) $/ -> $/ {
            take ｢&[%s].cando(\(%s, %s))[0]｣.sprintf: $1, $0, $2
        }
        # yeah, just some useful heuristics and brute force
        # ideally, it should work with QAST
    }

    for @wild-guesses -> $tweaked-code {
        my $wrapped-code = ‘with {’ ~ $tweaked-code ~ ‘}() { print “\0\0” ~ .line ~ “\0\0” ~ .file ~ “\0\0” }’;
        my $file = write-code $wrapped-code;
        LEAVE .unlink with $file;

        my $result = run-snippet $full-commit, $file, :!wipe, :!lock;
        if $result<exit-code> == 0 {
            my ($, $line, $file, $) = $result<output>.split: “\0\0”, 4; # hackety hack
            if $line and $file and $file.starts-with: ‘SETTING::’ {
                $file .= subst: /^‘SETTING::’/, ‘’;
                return “$BLOB-URL/$short-commit/$file#L$line”;
            }
        }
    }
    # Test the snippet itself
    my $file = write-code $code;
    my $result = run-snippet $full-commit, $file, :!wipe, :!lock;
    my $cry = ‘No idea, boss. Can you give me a Code object?’;
    if $result<exit-code> ≠ 0 {
        return (“$cry Output: {$result<output>}”
                but ProperStr($result<output>)) but PrettyLink({“$cry Output: $_”})
    }
    return $cry
}


Sourceable.new.selfrun: 'sourceable6', [ / s <before ':'> /,
                                         fuzzy-nick('sourceable6', 2) ];

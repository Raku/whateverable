#!/usr/bin/env perl6
# Copyright © 2016-2018
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
use Whateverable::Processing;
use Whateverable::Replaceable;
use Whateverable::Running;

use IRC::Client;
use Terminal::ANSIColor;

unit class Evalable does Whateverable does Whateverable::Replaceable;

method help($msg) {
    “Like this: {$msg.server.current-nick}: say ‘hello’; say ‘world’”
}

multi method irc-to-me($msg) {
    return self.process: $msg, $msg.text if $msg.args[1] !~~
                                /^ \s*[master|rakudo|r|‘r-m’|m|p6|perl6]‘:’\s /;
    self.make-believe: $msg, (‘camelia’,), {
        self.process: $msg, $msg.text
    }
}

#↓ Detect if somebody accidentally forgot “m:” or other command prefix
multi method irc-privmsg-channel($msg) {
    my $nonword-ratio = $msg.args[1].comb(/<-alpha -space>/) ÷ $msg.args[1].chars;
    nextsame if $nonword-ratio < 0.1; # skip if doesn't look like code at all
    nextsame if $msg.args[1] ~~ /^ \s*<[\w-]>+‘:’ /; # skip messages to other bots

    self.process: $msg, $msg.args[1], :good-only
}

method process($msg, $code, :$good-only?) {
    my $commit = %*BOT-ENV<commit>;
    my $file = process-code $code, $msg;
    LEAVE .unlink with $file;

    # convert to real id so we can look up the build
    my $full-commit  = to-full-commit $commit;
    my $short-commit = to-full-commit $commit, :short;

    if not build-exists $full-commit {
        return if $good-only;
        grumble “No build for $short-commit. Not sure how this happened!”
    }

    # actually run the code
    my $result = run-snippet $full-commit, $file;
    my $output = $result<output>;
    if $good-only and ($result<signal> ≤ 0 or $result<signal> == SIGHUP) {
        # forcefully proceed ↑ with non-zero signals (except sighupped timeouts)
        return if $result<signal>    ≠ 0;
        return if $result<exit-code> ≠ 0;
        return if !$output;
        return if $output ~~ /^‘WARNINGS for ’\N*\n‘Useless use’/;
        return if $output ~~ /^‘Potential difficulties:’/;
        return if $output ~~ /^‘Use of uninitialized value of type Any in string context.’/;
    }
    my $extra  = ‘’;
    if $result<signal> < 0 { # numbers less than zero indicate other weird failures
        $output = “Cannot test $full-commit ($output)”
    } else {
        $extra ~= “(exit code $result<exit-code>) ”     if $result<exit-code> ≠ 0;
        $extra ~= “(signal {Signal($result<signal>)}) ” if $result<signal>    ≠ 0
    }

    my $reply-start = “rakudo-moar $short-commit: OUTPUT: «$extra”;
    my $reply-end   = ‘»’;
    if $CONFIG<message-limit> ≥ ($reply-start, $output, $reply-end).map(*.encode.elems).sum {
        return $reply-start ~ $output ~ $reply-end # no gist
    }
    $reply-end = ‘…’ ~ $reply-end;
    my $extra-size = ($reply-start, $reply-end).map(*.encode.elems).sum;
    my $output-size = 0;
    my $SHORT-MESSAGE-LIMIT = $CONFIG<message-limit> ÷ 2;
    my $output-cut = $output.comb.grep({
        $output-size += .encode.elems;
        $output-size + $extra-size < $SHORT-MESSAGE-LIMIT
    })[0..*-2].join;
    $msg.reply: $reply-start ~ $output-cut ~ $reply-end;
    sleep 0.02;
    my $gist = ($extra ?? “$extra\n” !! ‘’) ~ colorstrip $output;
    (‘’ but ProperStr($gist)) but PrettyLink({ “Full output: $_” })
}


my %*BOT-ENV = commit => ‘HEAD’;

Evalable.new.selfrun: ‘evalable6’, [/ [ | \s*[master|rakudo|r|‘r-m’|m|p6|perl6]
                                        | e[val]?6? | what ] <before ‘:’> /,
                                    fuzzy-nick(‘evalable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

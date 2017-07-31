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

use lib ‘.’;
use Misc;
use Replaceable;
use Whateverable;

use IRC::Client;
use Terminal::ANSIColor;

unit class Evalable does Whateverable does Replaceable;

constant SHORT-MESSAGE-LIMIT = MESSAGE-LIMIT ÷ 2;

method help($msg) {
    “Like this: {$msg.server.current-nick}: say ‘hello’; say ‘world’”
}

multi method irc-to-me($msg) {
    if $msg.args[1] ~~ / ^ ‘m:’\s / {
        self.make-believe: $msg, (‘camelia’,), {
            # TODO exceptions here are not caught
            self.process: $msg, $msg.text
        }
        return
    }
    return if $msg.args[1].starts-with: ‘what,’;
    self.process: $msg, $msg.text
}

#↓ Detect if somebody accidentally forgot “m:” or other command prefix
multi method irc-privmsg-channel($msg) {
    nextsame if $msg.args[1] !~~ /
    ^ ‘say’ \s+
    <!before ‘I’ [\s | ‘'’]>
    [
        || [ [<:Uppercase> || ‘'’ || ‘"’ || ｢“｣ || ｢‘｣ ] .* $ ]
        || [ (.*) $ <?{$0.chars / $0.comb(/<-alpha -space>/) ≤ 10 }> ]
    ]
    <!after <[.!?]>>
    /;
    self.irc-to-me: $msg
}

method process($msg, $code is copy) {
    my $commit = ‘HEAD’;
    $code = self.process-code: $code, $msg;
    my $filename = self.write-code: $code;
    LEAVE { unlink $_ with $filename }

    # convert to real id so we can look up the build
    my $full-commit  = self.to-full-commit: $commit;
    my $short-commit = self.to-full-commit: $commit, :short;

    my $extra  = ‘’;
    my $output = ‘’;

    if not self.build-exists: $full-commit {
        $output = “No build for $short-commit. Not sure how this happened!”
    } else { # actually run the code
        my $result = self.run-snippet: $full-commit, $filename;
        $output = $result<output>;
        if $result<signal> < 0 { # numbers less than zero indicate other weird failures
            $output = “Cannot test $full-commit ($result<output>)”
        } else {
            $extra ~= “(exit code $result<exit-code>) ”     if $result<exit-code> ≠ 0;
            $extra ~= “(signal {Signal($result<signal>)}) ” if $result<signal>    ≠ 0
        }
    }

    my $reply-start = “rakudo-moar $short-commit: OUTPUT: «$extra”;
    my $reply-end = ‘»’;
    if MESSAGE-LIMIT ≥ ($reply-start, $output, $reply-end).map(*.encode.elems).sum {
        return $reply-start ~ $output ~ $reply-end
    }
    my $link = self.upload: {‘result’ => ($extra ?? “$extra\n” !! ‘’) ~ colorstrip($output),
                             ‘query’  => $msg.text, },
                            description => $msg.server.current-nick, :public;
    $reply-end = ‘…’ ~ $reply-end;
    my $extra-size = ($reply-start, $reply-end).map(*.encode.elems).sum;
    my $output-size = 0;
    my $output-cut = $output.comb.grep({
            $output-size += .encode.elems;
            $output-size + $extra-size < SHORT-MESSAGE-LIMIT
        })[0..*-2].join;
    $msg.reply: $reply-start ~ $output-cut ~ $reply-end;
    sleep 0.02;
    return “Full output: $link”;
}

Evalable.new.selfrun: ‘evalable6’, [‘m’, /eval6?/, fuzzy-nick(‘evalable6’, 2), ‘what’, ‘e’ ]

# vim: expandtab shiftwidth=4 ft=perl6

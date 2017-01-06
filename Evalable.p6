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
use Terminal::ANSIColor;

unit class Evalable is Whateverable;

constant SHORT-MESSAGE-LIMIT = MESSAGE-LIMIT / 2;

method help($message) {
    “Like this: {$message.server.current-nick}: say ‘hello’; say ‘world’”
};

multi method irc-to-me($message) {
    if $message.args[1] ~~ / ^ ‘m:’ / {
        my $update-promise = Promise.new;
        $!update-promise-channel.send: $update-promise;
        $message.irc.send-cmd: 'NAMES', $message.channel;
        start { # if this crashes it's not my fault
            await Promise.anyof($update-promise, Promise.in(4));
            $!users-lock.protect: {
                return if %!users{$message.channel}<camelia>;
            }
            my $value = self.process($message, $message.text);
            $message.reply: ResponseStr.new(:$value, :$message);
        }
        return;
    } else {
        my $value = self.process($message, $message.text);
        return ResponseStr.new(:$value, :$message);
    }
}

method process($message, $code is copy) {
    my $old-dir = $*CWD;
    my $commit = ‘HEAD’;

    my ($succeeded, $code-response) = self.process-code($code, $message);
    return $code-response unless $succeeded;
    $code = $code-response;

    my $filename = self.write-code($code);

    # convert to real id so we can look up the build
    my $full-commit = self.to-full-commit($commit);
    my $short-commit = self.to-full-commit($commit, :short);

    my $extra  = ‘’;
    my $output = ‘’;

    if not self.build-exists($full-commit) {
        $output = “No build for $short-commit. Not sure how this happened!”;
    } else { # actually run the code
        ($output, my $exit, my $signal, my $time) = self.run-snippet($full-commit, $filename);
        if $signal < 0 { # numbers less than zero indicate other weird failures
            $output = “Cannot test $full-commit ($output)”;
        } else {
            $extra ~= “(exit code $exit) ” if $exit != 0;
            $extra ~= “(signal {Signal($signal)}) ” if $signal != 0;
        }
    }

    my $reply-start = “rakudo-moar $short-commit: OUTPUT«$extra”;
    my $reply-end = ‘»’;
    if ($reply-start, $output, $reply-end).map(*.encode.elems).sum > MESSAGE-LIMIT {
        my $link = self.upload({‘result’ => ($extra ?? “$extra\n” !! ‘’) ~ colorstrip($output),
                                ‘query’  => $message.text, },
                               description => $message.server.current-nick, :public);
        $reply-end = ‘…’ ~ $reply-end;
        my $extra-size = ($reply-start, $reply-end).map(*.encode.elems).sum;
        my $output-size = 0;
        my $output-cut = $output.comb.grep(
            {
                $output-size += .encode.elems;
                $output-size + $extra-size < SHORT-MESSAGE-LIMIT
            })[0..*-2].join;
        $message.reply: $reply-start ~ $output-cut ~ $reply-end;
        sleep 0.02; # otherwise the output may be in the wrong order TODO is it a problem in IRC::Client?
        return “Full output: $link”;
    } else {
        return $reply-start ~ $output ~ $reply-end;
    }

    LEAVE {
        chdir $old-dir;
        unlink $filename if $filename.defined and $filename.chars > 0;
    }
}

# ↓ Here we will try to keep track of users on the channel.
#   This is a temporary solution. See this bug report:
#   * https://github.com/zoffixznet/perl6-IRC-Client/issues/29
has %!users;
has $!users-lock = Lock.new;
has $!update-promise-channel = Channel.new;
has %!temp-users;

method irc-n353 ($e) {
    my $channel = $e.args[2];
    # Try to filter out privileges ↓
    my @nicks = $e.args[3].words.map: { m/ (<[\w \[ \] \ ^ { } | ` -]>+) $/[0].Str };
    %!temp-users{$channel} //= SetHash.new;
    %!temp-users{$channel}{@nicks} = True xx @nicks;
}

method irc-n366 ($e) {
    my $channel = $e.args[1];
    $!users-lock.protect: {
        %!users{$channel} = %!temp-users{$channel};
        %!temp-users{$channel}:delete;
    };
    loop {
        my $promise = $!update-promise-channel.poll;
        last if not defined $promise;
        try { $promise.keep } # could be already kept
    }
}

Evalable.new.selfrun(‘evalable6’, [‘m’, /eval6?/, fuzzy-nick(‘evalable6’, 2), ‘what’, ‘e’ ]);

# vim: expandtab shiftwidth=4 ft=perl6

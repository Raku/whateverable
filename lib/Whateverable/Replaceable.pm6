# Copyright © 2016-2017
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

use Whateverable::Bits;

#↓ Keep track of users and pretend to be someone if needed
unit role Whateverable::Replaceable;

# This is a temporary solution. See this bug report:
# * https://github.com/zoffixznet/perl6-IRC-Client/issues/29

has %!users;
has $!users-lock = Lock.new;
has $!update-promise-channel = Channel.new;
has %!temp-users;

method make-believe($msg, @nicks, &play, :$timeout = 4) {
    my $update-promise = Promise.new;
    $!update-promise-channel.send: $update-promise;
    $msg.irc.send-cmd: ‘NAMES’, $msg.channel;
    my $x = %*BOT-ENV;
    start {
        my %*BOT-ENV = $x; # TODO … yeah, I don't know
        await Promise.anyof: $update-promise, Promise.in: $timeout;
        $!users-lock.protect: {
            return if any %!users{$msg.channel}{@nicks}:exists
        }
        try {
            $msg.reply: $_ but Reply($msg) with play;
            CATCH { default { $msg.reply: self.handle-exception: $_, $msg } }
        }
    }
    Nil
}

method list-users($msg, $channel=$msg.channel, :$timeout = 4) {
    my $update-promise = Promise.new;
    $!update-promise-channel.send: $update-promise;
    $msg.irc.send-cmd: ‘NAMES’, $msg.channel;
    start {
        await Promise.anyof: $update-promise, Promise.in: $timeout;
        $!users-lock.protect: {
            %!users{$channel}.clone
        }
    }
}


method irc-n353($e) { # one or more messages
    my $irc-channel = $e.args[2];
    # Try to filter out privileges ↓
    my @nicks = $e.args[3].words.map: { m/ (<[\w \[ \] \ ^ { } | ` -]>+) $ /[0].Str };
    $!users-lock.protect: {
        %!temp-users{$irc-channel} //= SetHash.new;
        %!temp-users{$irc-channel}{@nicks} = True xx @nicks
    }
}

method irc-n366($e) { # final message
    my $irc-channel = $e.args[1];
    $!users-lock.protect: {
        %!users{$irc-channel} = %!temp-users{$irc-channel};
        %!temp-users{$irc-channel}:delete
    }
    loop {
        my $promise = $!update-promise-channel.poll;
        last without $promise;
        try { $promise.keep } # could be already kept
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

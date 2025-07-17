# Copyright © 2016-2019
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

#| Keep track of users
unit role Whateverable::Userlist;

# This is a temporary solution (aha, sure). See this bug report:
# * https://github.com/zoffixznet/perl6-IRC-Client/issues/29

# We'll need at least one lock no matter what, so let's
# use *just* one to make things simpler
has %!userlist; #= %( channel0 => %(:user0, …), … );
has $!userlist-lock = Lock.new;

method userlist($msg) {
    $!userlist-lock.protect: {
        %!userlist{$msg.channel} // %()
    }
}

#| Impersonate other bots
method make-believe($msg, @nicks, &play) {
    my @found-nicks = self.userlist($msg){@nicks}:exists;
    if @found-nicks.none {
        $_ but Reply($msg) with play;
    }
}

#| Nick change event
method irc-nick($event) {
    $!userlist-lock.protect: {
        for %!userlist.keys -> $channel {
            %!userlist{$channel}{$event.nick}:delete;
            %!userlist{$channel}{$event.new-nick} = True;
        }
    }
    $.NEXT
}
method irc-join($event) {
    $!userlist-lock.protect: {
        if not %!userlist{$event.channel} or (^30).pick == 0 { # self-healing behavior
            $event.irc.send-cmd: ‘NAMES’, $event.channel;
        }
        %!userlist{$event.channel}{$event.nick} = True;
    }
    $.NEXT
}
method irc-part($event) {
    $!userlist-lock.protect: {
        %!userlist{$event.channel}{$event.nick}:delete;
    }
    $.NEXT
}
method irc-quit($event) {
    $!userlist-lock.protect: {
        for %!userlist.keys -> $channel {
            %!userlist{$channel}{$event.nick}:delete;
        }
    }
    $.NEXT
}

has %!userlist-temp; # for storing partial messages

#| Receive a user list (one or more messages)
method irc-n353($event) {
    my $channel = $event.args[2];
    # Try to filter out privileges ↓
    my @nicks = $event.args[3].words.map: { m/ (<.&irc-nick>) $ /[0].Str };
    $!userlist-lock.protect: {
        %!userlist-temp{$channel}{@nicks} = True xx @nicks
    }
}

# XXX What if we receive a `join` right here? Whatever…

#| Receive a user list (final message)
method irc-n366($event) {
    my $channel = $event.args[1];
    $!userlist-lock.protect: {
        %!userlist{$channel} = %!userlist-temp{$channel};
        %!userlist-temp{$channel}:delete
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

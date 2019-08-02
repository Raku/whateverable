#!/usr/bin/env perl6
# Copyright © 2019
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
use Whateverable::FootgunDB;

use IRC::Client;
use JSON::Fast;

unit class Tellable does Whateverable;

my $db-seen = FootgunDB.new: name => ‘tellable-seen’;
my $db-tell = FootgunDB.new: name => ‘tellable-tell’;

method help($msg) {
    ‘Like this: .tell AlexDaniel your bot is broken’
}

#| listen for messages
multi method irc-privmsg-channel($msg) {
    $db-seen.read-write: {
        .{$msg.nick} = {
            text      => $msg.text,
            channel   => $msg.channel,
            timestamp => timestampish,
            nick      => $msg.nick,
        }
    }
    my %mail = $db-tell.read;
    if %mail{$msg.nick} {
        for %mail{$msg.nick}.list {
            my $text = sprintf ‘%s %s <%s> %s’, .<timestamp channel from text>;
            $msg.irc.send-cmd: 'PRIVMSG', $msg.channel, $text, :server($msg.server)
        }
        %mail{$msg.nick}:delete;
        $db-tell.write: %mail;
    }
    $.NEXT
}

#`｢ TODO implement proper user tracking first
#| automatic tell
multi method irc-privmsg-channel($msg where { m:r/^ \s* $<who>=<.&irc-nick> ‘:’+ \s+ (.*) $/ }) {
    my $who = $<who>;
    # TODO use `does Replaceable`
    return $.NEXT if $who ~~ list-users.any; # still on the channel
    my %seen := $db-seen.read;
    return $.NEXT unless %seen{$who}:exists; # haven't seen them talk ever
    my $last-seen-duration = DateTime.now(:0timezone) - DateTime.new(%seen{$who}<timestamp>);
    return $.NEXT if $last-seen-duration ≥ 60×60×24 × 3; # haven't seen for months
    self.irc-to-me: $msg;
    $.NEXT
}｣

#| .seen
multi method irc-privmsg-channel($msg where .args[1] ~~ /^ ‘.seen’ \s+ (.*) /) {
    $msg.text = ~$0;
    self.irc-to-me: $msg
}

#| .tell
multi method irc-privmsg-channel($msg where .args[1] ~~ /^ ‘.’[to|tell|ask] \s+ (.*) /) {
    $msg.text = ~$0;
    self.irc-to-me: $msg
}

sub did-you-mean-seen($who, %seen) {
    did-you-mean $who, %seen.sort(*.value<timestamp>).reverse.map(*.key),
                 :max-distance(2)
}

#| seen
multi method irc-to-me($msg where { m:r/^ \s* [seen \s+]?
                                          $<who>=<.&irc-nick> <[:,]>* \s* $/ }) {
    my $who = ~$<who>;
    my %seen := $db-seen.read;
    my $entry = %seen{$who};
    without $entry {
        return “I haven't seen $who around”
        ~ maybe ‘, did you mean %s?’, did-you-mean-seen $who, %seen
    }
    “I saw $who $entry<timestamp> in $entry<channel>: <$who> $entry<text>”
}

#| tell
multi method irc-to-me($msg where { m:r/^ \s* [[to|tell|ask] \s+]?
                                          $<who>=<.&irc-nick> <[:,]>* \s+ .* $/ }) {
    my $who = ~$<who>;
    return ‘Thanks for the message’ if $who eq $msg.server.current-nick;
    return ‘I'll pass that message to your doctor’ if $who eq $msg.nick and not %*ENV<TESTABLE>;
    my %seen := $db-seen.read;
    without %seen{$who} {
        return “I haven't seen $who around”
        ~ maybe ‘, did you mean %s?’, did-you-mean-seen $who, %seen
    }
    $db-tell.read-write: {
        .{$who}.push: {
            text      => $msg.text,
            channel   => $msg.channel,
            timestamp => timestampish,
            from      => $msg.nick,
        }
    }
    “I'll pass your message to $who”
}

my %*BOT-ENV = %();

Tellable.new.selfrun: ‘tellable6’, [/ [to|tell|ask|seen] 6? <before ‘:’> /,
                                    fuzzy-nick(‘tellable6’, 3)];

# vim: expandtab shiftwidth=4 ft=perl6

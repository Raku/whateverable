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
use Whateverable::Discordable;
use Whateverable::FootgunDB;
use Whateverable::Userlist;

use IRC::Client:ver<4.0.14+>:auth<zef:lizmat>;
use JSON::Fast:ver<0.19+>:auth<cpan:TIMOTIMO>;

unit class Tellable does Whateverable does Whateverable::Userlist;

#| Timeout used for not passing the message if the user
#| reacts immediately
my $heard-timeout = 60 × 10; # should be a few minutes

my $db-seen = FootgunDB.new: name => ‘tellable-seen’;
my $db-tell = FootgunDB.new: name => ‘tellable-tell’;

method help($msg) {
    ‘Like this: .tell AlexDaniel your bot is broken’
}

#| normalize nicknames, somewhat
sub normalize-weirdly($nick) {
    # We knowingly ignore CASEMAPPING and its bullshit rules.
    # Instead we'll do our own crazy stuff in order to DWIM.
    # These rules are based on messages that were never delivered.

    # XXX not using s/// because there's a sub s (rakudo/rakudo#3111)
    $_ = $nick.fc;
    s:!g/‘[m]’$//;      # matrix users
    s:!g/\W+$//;        # garbage at the end
    s:!g/^\W+//;        # garbage at the beginning
    s:g/‘-’//;          # hyphens
    s:g/‘_’//;          # underscores
    s:g/(.)$0+/$0/;     # accidentally doubled characters
    s:g/\d// if S:g/\d//.chars > 4; # remove numbers if we still have letters
    .chars ≥ 2 ?? $_ !! $nick;      # return original if too much was removed
}

sub guest-like($nick) { so $nick ~~ /^Guest\d/ }

#| listen for messages and deliver stuff
multi method irc-privmsg($msg where IRC::Client::Message::Privmsg::Channel) {
    return $.NEXT if guest-like $msg.nick;
    my $normalized = normalize-weirdly $msg.nick;
    $db-seen.read-write: {
        .{$normalized} = {
            text      => $msg.text,
            channel   => $msg.channel,
            timestamp => timestampish,
            nick      => $msg.nick,
            bridged   => ($msg.nick ~~ FromDiscord).so,
        }
    }
    my %mail = $db-tell.read;
    if %mail{$normalized} {
        for %mail{$normalized}.list {
            # don't send messages if the person replies real quick
            next if .<heard> and timestampish() - DateTime.new(.<timestamp>) ≤ $heard-timeout
                    and .<channel> eq $msg.channel and not %*ENV<TESTABLE>;
            my $text = sprintf ‘%s %s <%s> %s’, .<timestamp channel from text>;
            $msg.irc.send-cmd: :server($msg.server), 'PRIVMSG', $msg.channel,
                               $text but PrettyLink({ “hey {$msg.nick}, you have a message: $_” });
            # you *have* to start the message with “hey” or something
            # similar, otherwise two bots can get into an infiloop
            sleep 0.3;
        }
        %mail{$normalized}:delete;
        $db-tell.write: %mail;
    }
    $.NEXT
}


#| automatic tell
multi method irc-privmsg-channel($msg where { m:r/^ \s* $<who>=<.&irc-nick> ‘:’+ \s+ (.*) $/ }) {
    my $who = $<who>;
    return $.NEXT if self.userlist($msg){$who}; # still on the channel
    my $normalized = normalize-weirdly $who;
    my %seen := $db-seen.read;
    return $.NEXT unless %seen{$normalized}:exists; # haven't seen them talk ever
    return $.NEXT if %seen{$normalized}<bridged>; # we don't know status of bridged users
    # TODO ↓ this should go through all nicknames on the channel
    my $previous-nick = %seen{$normalized}<nick>;
    return $.NEXT if self.userlist($msg){$previous-nick}; # previous nickname still on the channel
    my $last-seen-duration = DateTime.now(:0timezone) - DateTime.new(%seen{$normalized}<timestamp>);
    return $.NEXT if $last-seen-duration ≥ 60×60×24 × 28 × 3; # haven't seen for months
    $msg.text = ‘tell ’ ~ $msg.text;
    self.irc-to-me: $msg;
}

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
    did-you-mean $who, %seen.sort(*.value<timestamp>).reverse.map(*.value<nick>),
                 :max-distance(3)
}

#| seen
multi method irc-to-me($msg where { m:r/^ \s* [seen \s+]?
                                          $<who>=<.&irc-nick> <[:,]>* \s* $/ }) {
    my $who = ~$<who>;
    my %seen := $db-seen.read;
    my $entry = %seen{normalize-weirdly $who};
    without $entry {
        return ‘I haven't seen any guests around’ if guest-like $who;
        return “I haven't seen $who around”
        ~ maybe ‘, did you mean %s?’, did-you-mean-seen $who, %seen
    }

    # Format CTCP ACTION aka /me
    my $said = $entry<text> ~~ /^ \x[01] ‘ACTION ’ <( .* )> \x[01] $/ ??
        “* $entry<nick> $/” !!
        “<$entry<nick>> $entry<text>”;

    “I saw $who $entry<timestamp> in $entry<channel>: $said”
}

#| tell
multi method irc-to-me($msg where { m:r/^ \s* [[to|tell|ask] \s+]? $<text>=[
                                           $<who>=<.&irc-nick> <[:,]>* \s+ .*
                                          ]$/ }) {
    my $who = ~$<who>;
    my $text = ~$<text>;
    my $normalized = normalize-weirdly $who;
    return ‘Thanks for the message’ if $who eq $msg.server.current-nick;
    return ‘I'll pass that message to your doctor’ if $who eq $msg.nick and not %*ENV<TESTABLE>;
    my %seen := $db-seen.read;
    without %seen{$normalized} {
        return ‘Can't pass messages to guests’ if guest-like $who;
        return “I haven't seen $who around”
        ~ maybe ‘, did you mean %s?’, did-you-mean-seen $who, %seen
    }
    # TODO ↓ this should go through all nicknames on the channel
    my $previous-nick = %seen{$normalized}<nick>;
    my $heard = so any self.userlist($msg){$who, $previous-nick};
    $db-tell.read-write: {
        .{$normalized}.push: {
            text      => $text,
            channel   => $msg.channel,
            timestamp => timestampish,
            from      => $msg.nick,
            to        => $who,
            heard     => $heard,
        }
    }
    “I'll pass your message to {%seen{$normalized}<nick>}”
}


{
    # Renormalize on startup in case the rules were updated
    $db-tell.write:   $db-tell.read.values».list.flat.classify: {
        normalize-weirdly .<to>
    };
    $db-seen.write: %($db-seen.read.values.map: {
        normalize-weirdly(.<nick>) => $_
    });
}

Tellable.new.selfrun: ‘tellable6’, [/ [to|tell|ask|seen] 6? <before ‘:’> /,
                                    fuzzy-nick(‘tellable6’, 1)];

# vim: expandtab shiftwidth=4 ft=perl6

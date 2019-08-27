# Copyright © 2019
#     Tobias Boege <tobs@taboege.de>
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

use IRC::Client::Message;

my constant ChannelMessage = IRC::Client::Message::Privmsg::Channel;

#| Transparently handle messages from the discord bridge.
unit role Whateverable::Discordable;

#| Role mixed into .nick of messages processed by Discordable
my role FromDiscord is export { }

#| Nick of the discord bridge bot.
my constant DISCORD-BRIDGE = any(‘discord6’, ‘discord61’);

#| Unpack messages from the discord bridge and restart processing.
multi method irc-privmsg-channel(ChannelMessage $msg where .nick eq DISCORD-BRIDGE) {
    # Extract the real message and sender.
    return $.NEXT unless $msg.text ~~ m/^
            ‘<’ $<nick>=<-[>]>+ ‘>’ \s+
            $<text>=.*
        $/;
    # Since this is a channel message, we can also put the discord username
    # into $.nick. It is not used for routing the message on IRC, only to
    # address the user in the reply.
    my $bridged-msg = $msg.clone:
        nick => ~$<nick> but FromDiscord,
        text => ~$<text>,
        args => [$msg.channel, ~$<text>],
    ;

    with $.irc.^private_method_table<handle-event> {
        .($.irc, $bridged-msg)
    }

    # Do nothing with the bridge's message.
    Nil
}

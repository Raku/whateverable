#!/usr/bin/env perl6
# Copyright © 2017-2020
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

use Cro::HTTP::Router;
use Cro::HTTP::Server;

sub listen-to-webhooks(…) {
    my $channel = Channel.new;

    my $application = route {
        get {
            with process-github-hook $_, $CONFIG<squashable><secret>, $msg.irc, $CHANNEL {
                $channel.send: $_
            }
        }
    };

    my $webhook-listener = Cro::HTTP::Server.new(
        host => $CONFIG<buildable><host>,
        port => $CONFIG<buildable><port>,
        :$application,
    );
    $webhook-listener.start;
    $channel
}

sub process-webhook($body, $secret, $irc, $channel) {
    use Digest::SHA;
    use Digest::HMAC;

    my $body = $request.data;
    $body .= subbuf: 0..^($body - 1) if $body[*-1] == 0; # TODO trailing null byte. Why is it there?

    my $hmac = ‘sha1=’ ~ hmac-hex $secret, $body, &sha1;
    if $hmac ne $request.headers<X-Hub-Signature> {
        response.status = 400;
        content ‘Signatures didn't match’;
        return
    }

    my $data = try from-json $body.decode;
    without $data {
        response.status = 400;
        content ‘Invalid JSON’;
        return
    }

    if $data<zen>:exists {
        my $text = “Webhook for {$data<repository><full_name>} is now ”
                 ~ ($data<hook><active> ?? ‘active’ !! ‘inactive’) ~ ‘! ’
                 ~ $data<zen>;
        $irc.send: :$text, where => $channel;
    }

    content ‘’;
    $data
}

# vim: expandtab shiftwidth=4 ft=perl6

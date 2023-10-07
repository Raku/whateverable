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

use Whateverable::Config;

unit module Whateverable::Webhooks;


class StrictTransportSecurity does Cro::Transform {
    has Str:D $.secret is required;

    method consumes() { Cro::TCP::Message }
    method produces() { Cro::TCP::Message }

    method transformer(Supply $pipeline --> Supply) {
        supply {
            whenever $pipeline -> $response {
                $response.append-header:
                'Strict-Transport-Security',
                "max-age=$!max-age";
                emit $response;
            }
        }
    }
}

#| Listen to github webhooks. Returns a channel that will provide
#| payload objects.
sub listen-to-webhooks($host, $port, $secret, $channel, $irc) is export {
    my $c = Channel.new;

    my $application = route {
        post {
            my $CHANNEL = %*ENV<DEBUGGABLE> ?? $CONFIG<cave> !! $channel;
            with process-webhook $secret, $CHANNEL, $irc {
                $c.send: $_
            }
        }
    };

    my $webhook-listener = Cro::HTTP::Server.new(
        :$host, :$port,
        :$application,
        # TODO before => WebhookChecker.new($secret)
    );
    $webhook-listener.start;
    $c
}

#| GitHub-specific processing of webhook payloads
sub process-webhook($secret, $channel, $irc) {
    use Digest::SHA;
    use Digest::HMAC;

    my $body = request-body -> Blob { $_ };
    dd $body;
    $body .= subbuf: 0..^($body - 1) if $body[*-1] == 0; # TODO trailing null byte. Why is it there?

    my $hmac = ‘sha1=’ ~ hmac-hex $secret, $body, &sha1;
    if $hmac ne request.headers<X-Hub-Signature> {
        bad-request ‘text/plain’, ‘Signatures didn't match’;
        return
    }

    my $data = try from-json $body.decode;
    without $data {
        bad-request ‘text/plain’, ‘Signatures didn't match’;
        return
    }

    if $data<zen>:exists {
        my $text = “Webhook for {$data<repository><full_name>} is now ”
                 ~ ($data<hook><active> ?? ‘active’ !! ‘inactive’) ~ ‘! ’
                 ~ $data<zen>;
        $irc.send: :$text, where => $channel;
    }

    content ‘text/plain’, ‘’;
    $data
}

# vim: expandtab shiftwidth=4 ft=perl6

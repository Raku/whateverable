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

use Whateverable;
use Misc;

use IRC::Client;

unit class Quotable does Whateverable;

my $CACHE-DIR = ‘data/irc/’.IO;
my $LINK      = ‘https://irclog.perlgeek.de’;

method help($msg) {
    “Like this: {$msg.server.current-nick}: /^ ‘bisect: ’ /”
}

my atomicint $hack = 0;
multi method irc-to-me($msg where /^ \s* [ || ‘/’ $<regex>=[.*] ‘/’
                                           || $<regex>=[.*?]       ] \s* $/) {
    $hack ⚛= 0;
    my $regex = $<regex>;
    my $messages = $CACHE-DIR.dir(test => *.ends-with: ‘.total’)».slurp».trim».Int.sum;
    $msg.reply: “OK, working on it! This may take up to three minutes ($messages messages to process)”;
    my %channels = await do for $CACHE-DIR.dir(test => *.ends-with: ‘.cache’) {
        my $channel = .basename.subst(/ ^‘#’ /, ‘’).subst(/ ‘.cache’$ /, ‘’);
        start “result-#$channel.md” => process-channel $_, $channel, ~$regex
    }
    ‘’ but FileStore(%channels)
}

sub process-channel($file, $channel, $regex-str) {
    perl6-grep($file, $regex-str, :complex, hack => $hack⚛++).map({
        my @parts = .split: “\0”; # text, id, date
        my $backticks = ｢`｣ x (1 + (@parts[0].comb(/｢`｣+/) || ‘’).max.chars);
        # TODO proper escaping
        @parts ≤ 1 ?? $_
        !! “[$backticks @parts[0] $backticks]($LINK/$channel/@parts[2]#i_@parts[1])<br>”
    }).join(“\n”)
}

Quotable.new.selfrun: ‘quotable6’, [ / quote6? <before ‘:’> /,
                                     fuzzy-nick(‘quotable6’, 1) ]

# vim: expandtab shiftwidth=4 ft=perl6

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
use Whateverable::Bits;
use Whateverable::Running;

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
    my @processed = await do for $CACHE-DIR.dir(test => *.ends-with: ‘.cache’) {
        my $channel = .basename.subst(/ ^‘#’ /, ‘’).subst(/ ‘.cache’$ /, ‘’);
        start process-channel $_, $channel, ~$regex
    }
    my $date-min = @processed»<date-min>.min;
    my $date-max = @processed»<date-max>.max;
    my $count    = @processed»<count>.sum;
    my %channels = @processed.map: {“result-#{.<channel>}.md” => .<gist>};
    return ‘Found nothing!’ unless $count;
    my $peek = $count > 1 ?? “$count messages ($date-min⌁$date-max)”
                          !! “$count message ($date-min)”;
    (‘’ but FileStore(%channels)) but PrettyLink({“$peek: $_”})
}

sub process-channel($file, $channel, $regex-str) {
    my $count = 0;
    my $date-min;
    my $date-max;
    my $gist = perl6-grep($file, $regex-str, :complex, hack => $hack⚛++).map({
        my ($text, $id, $date) = .split: “\0”;
        $count++;
        $date-min min= $date;
        $date-max max= $date;
        my $backticks = ｢`｣ x (1 + ($text.comb(/｢`｣+/) || ‘’).max.chars);
        # TODO proper escaping
        $id.defined.not || $date.defined.not
        ?? $_ !! “[$backticks $text $backticks]($LINK/$channel/$date#i_$id)<br>”
    }).join(“\n”);
    $gist = ‘Found nothing!’ unless $gist;

    %(:$channel, :$count, :$date-min, :$date-max, :$gist)
}


my %*BOT-ENV;

Quotable.new.selfrun: ‘quotable6’, [ / quote6? <before ‘:’> /,
                                     fuzzy-nick(‘quotable6’, 1) ]

# vim: expandtab shiftwidth=4 ft=perl6

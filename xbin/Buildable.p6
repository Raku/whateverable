#!/usr/bin/env perl6
# Copyright © 2017-2020
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
use Whateverable::Building;
use Whateverable::Config;
use Whateverable::Webhooks;

use IRC::Client;

unit class Buildable does Whateverable;

method help($msg) {
    “Like this: {$msg.server.current-nick}: info”
}

my $l = Lock.new;
my $building;
my $packing;

multi method irc-to-me($msg where /:i [status|info|builds|stat]/) {
    my $projects = $CONFIG<projects>.keys.sort.reverse.map({ # XXX .reverse to make rakudo-moar first
        my $total-size = 0;
        my $files = 0;
        for dir $CONFIG<projects>{$_}<archives-path> {
            $total-size += .s unless .l;
            $files++;
        }
        “$files $_ builds ({round $total-size ÷ 10⁹, 0.1} GB)”
    }).join: ‘, ’;

    my $activity = ‘’;
    $l.protect: {
        $activity = ‘(⏳ Packing…) ’  with $packing;
        $activity = ‘(⏳ Building…) ’ with $building;
        .then: { $msg.reply: ‘Done!’ } with $packing // $building;
    }
    $activity ~ $projects
}

multi method keep-building($msg) {
    # TODO multi-server setup not supported (this will be irrelevant after #284)
    my $channel = listen-to-webhooks
        |$CONFIG<buildable><host port secret channel>,
        $msg.irc,
    ;

    #sleep 60 × 5; # let other bots start up and stuff
    react {
        whenever $channel {
            say $_;
            #$l.protect: { $building = Promise.new };
            # build-all
            #$l.protect: { $building.keep };
        }
        whenever Supply.interval: 60 × 30 {
            $l.protect: { $building = Promise.new };
            # build-all
            $l.protect: { $building.keep; $building = Nil };
        }
        whenever Supply.interval: 60 × 60 {
            $l.protect: { $packing = Promise.new };
            #pack-all
            $l.protect: {  $packing.keep;  $packing = Nil };
        }
    }

    CATCH { default {
        start { sleep 20; exit }; # restart itself
        self.handle-exception: $_, $msg
    } }
}

multi method irc-connected($msg) {
    once start self.keep-building: $msg
}


Buildable.new.selfrun: ‘buildable6’, [ / build[s]?6? <before ‘:’> /,
                                       fuzzy-nick(‘buildable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

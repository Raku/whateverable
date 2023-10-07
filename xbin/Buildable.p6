#!/usr/bin/env perl6
# Copyright © 2017-2023
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

use IRC::Client;

unit class Buildable does Whateverable;

method help($msg) {
    “Like this: {$msg.server.current-nick}: info”
}

my $meta-lock  = Lock.new;
my $building = Promise.kept;
my $packing  = Promise.kept;

my $trigger-supplier = Supplier.new;
my $trigger-supply = $trigger-supplier.Supply;

sub get-projects() {
    $CONFIG<projects>.keys.sort.reverse # XXX .reverse to make rakudo-moar first
}

multi method irc-to-me($msg where /:i [status|info|builds|stats?]/) {
    $trigger-supplier.emit(True);

    my $projects = get-projects.map({
        my $total-size = 0;
        my $files = 0;
        my $builds = 0;
        for dir $CONFIG<projects>{$_}<archives-path> {
            $total-size += .s unless .l;
            $files++ unless .l;
            $builds++ if .l or .ends-with: '.tar.zst';
        }
        “$builds $_ builds, $files archives ({round $total-size ÷ 10⁹, 0.1} GB)”
    }).join: ‘; ’;

    my $activity = ‘’;
    $meta-lock.protect: {
        if $building.status == Planned {
            $activity ~= ‘(⏳ Building…) ’;
            $building.then: { $msg.reply: ‘Done building!’ };
        }
        if $packing.status == Planned {
            $activity ~= ‘(📦 Packing…) ’;
            $packing.then: { $msg.reply: ‘Done packing!’  };
        }
    }
    $activity ||= ‘(😴 Idle) ’;
    $activity ~ $projects
}

ensure-config;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
my $application = route {
    get  -> { $trigger-supplier.emit(True); content 'text/html', 'OK' }
    post -> { $trigger-supplier.emit(True); content 'text/html', 'OK' }
}
my Cro::Service $service = Cro::HTTP::Server.new:
    :host($CONFIG<buildable><host>), :port($CONFIG<buildable><port>), :$application;
$service.start;


multi method keep-building($msg) {
    my $bleed = Supplier.new;
    react {
        whenever $bleed {} # do nothing, just ignore values that are bled
        whenever Supply.interval: 60 × 30 {
            $trigger-supplier.emit(True);
        }
        whenever $trigger-supply.throttle: 1, ({
            await $meta-lock.protect: { $building };
            # XXX Ideally this should use :vent-at(0), but that is a magical
            #     value in Rakudo. So, for now, it does one extra `git pull`
            #     after repeated webhooks, but that's not bad (just unnecessary).
            #     https://github.com/rakudo/rakudo/issues/5358
        }), :vent-at(1), :bleed($bleed) {
            $meta-lock.protect: {
                $building = start { build-all-commits $_ for < rakudo-moar > #`｢TODO get-projects()｣ };
                whenever $building {}
            }
        }
        whenever Supply.interval: 60 × 60 {
            $meta-lock.protect: {
                leave if $packing.status == Planned;
                $packing = start { pack-all-builds $_ for get-projects() };
                whenever $packing {}
            };
        }
    }

    CATCH { default {
        note $_;
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

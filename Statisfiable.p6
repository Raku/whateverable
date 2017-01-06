#!/usr/bin/env perl6
# Copyright © 2016
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
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

use lib ‘.’;
use Whateverable;

use SVG;
use SVG::Plot;
use JSON::Fast;
use IRC::Client;

unit class Statisfiable is Whateverable;

constant RAKUDO-CURRENT = “{WORKING-DIRECTORY}/rakudo”.IO.absolute;
constant RANGE          = ‘2014.01..HEAD’;
constant STATS-LOCATION = ‘./stats’.IO.absolute;

has %stats;

method TWEAK {
    mkdir STATS-LOCATION if STATS-LOCATION.IO !~~ :d;
    if “{STATS-LOCATION}/” {
        %stats<core>    = from-json slurp “{STATS-LOCATION}/core” if “{STATS-LOCATION}/core”.IO.e;
        %stats<core>    //= %();
        %stats<install> = from-json slurp “{STATS-LOCATION}/install” if “{STATS-LOCATION}/install”.IO.e;
        %stats<install> //= %();
    }
}

method help($message) {
    “Available stats: core (CORE.setting size), install (size of the whole installation), …”
}

multi method irc-to-me($message where /:i [ core | install ] /) {
    my ($value, %additional-files) = self.process($message, $message.text);
    return ResponseStr.new(:$value, :$message, :%additional-files);
}

multi method process($message, $query) {
    $message.reply: ‘OK! Working on it…’;

    my $type = $query ~~ /:i core / ?? ‘core’ !! ‘install’;
    my $zero = $query ~~ / 0 / ?? 0 !! Nil;
    my %data := %stats{$type};

    my @git = ‘git’, ‘--git-dir’, “{RAKUDO-CURRENT}/.git”, ‘--work-tree’, RAKUDO-CURRENT;
    my @command = |@git, ‘log’, ‘-z’, ‘--pretty=%H’, RANGE;

    my $let's-save = False;
    my @results;
    for run(:out, |@command).out.split(0.chr, :skip-empty) {
        next unless $_;
        my $full  = $_;
        #my $short = self.to-full-commit($_, :short);

        my $size;
        if %data{$full}:exists {
            $size = %data{$full};
        } else {
            if self.build-exists($full) {
                if ($type eq ‘core’) { # core
                    $size = self.run-smth: $full, {
                        my $file = “$_/share/perl6/runtime/CORE.setting.moarvm”.IO;
                        $file.IO.e ?? $file.IO.s ÷ 10⁶ !! Nil
                    }
                } else { # install
                    $size = self.run-smth: $full, {
                        # ↓ scary, but works
                        Rakudo::Internals.DIR-RECURSE($_).map({ .IO.s }).sum ÷ 10⁶
                    }
                }
            }
            %data{$full} = $size;
            $let's-save = True;
        }
        @results.push: ($full, $size) if $size && ($type eq ‘core’ or $size > 10);
    }

    spurt “{STATS-LOCATION}/$type”, to-json %data if $let's-save;


    my $pfilename = ‘plot.svg’;
    my $title = $type eq ‘core’ ?? ‘CORE.setting.moarvm file size (MB)’
                                !! ‘Installation size (MB)’;
    my @values = @results.reverse.map({.[1]});
    my @labels = @results.reverse.map({.[0].substr(0,8)});

    my $plot = SVG::Plot.new(
        width      => 1000,
        height     => 800,
        min-y-axis => $zero,
        :$title,
        values     => (@values,),
        :@labels,
        background => ‘white’,
    ).plot(:lines);
    my %graph = $pfilename => SVG.serialize($plot);

    my $msg-response = @results.reverse.map({.join: ‘ ’}).join: “\n”;

    ($msg-response, %graph)
}

multi method irc-to-me($msg) {
    ResponseStr.new(value => ‘Huh? ’ ~ self.help($msg), message => $msg)
}

Statisfiable.new.selfrun(‘statisfiable6’, [/stat6?/, fuzzy-nick(‘statisfiable6’, 3) ]);

# vim: expandtab shiftwidth=4 ft=perl6

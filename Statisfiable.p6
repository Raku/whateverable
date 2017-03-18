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

use lib ‘.’;
use Misc;
use Whateverable;

use IRC::Client;
use JSON::Fast;
use SVG::Plot;
use SVG;

unit class Statisfiable does Whateverable;

constant RANGE          = ‘2014.01..HEAD’;
constant STATS-LOCATION = ‘./stats’.IO.absolute;

constant OPTIONS = %(
    core         => ‘CORE.setting.moarvm file size (MB)’,
#   ‘core.lines’ => ‘Lines in CORE.setting.moarvm file (count)’,
    install      => ‘Space taken by a full installation (MB)’,
    libmoar      => ‘libmoar.so file size (MB)’,
);

has %stats;
has %stat-locks;

method TWEAK {
    mkdir STATS-LOCATION if STATS-LOCATION.IO !~~ :d;
    for OPTIONS.keys {
        %stat-locks{$_} = Lock.new;
        %stats{$_} = “{STATS-LOCATION}/$_”.IO.e
          ?? from-json slurp “{STATS-LOCATION}/$_”
          !! %()
    }
}

method help($) {
    ‘Available stats: ’ ~ (
        ‘core (CORE.setting size)’,
#        ‘core.lines (lines in CORE.setting)’,
        ‘install (size of the installation)’,
        ‘libmoar (libmoar.so size)’,
    ).join: ‘, ’
}

multi method stat-for-commit(‘core’, $full-hash) {
    self.run-smth: $full-hash, {
        my $file = “$_/share/perl6/runtime/CORE.setting.moarvm”.IO;
        $file.IO.e ?? $file.IO.s ÷ 10⁶ !! Nil
    }
}

#multi method stat-for-commit(‘core.lines’, $full-hash) {
#    # TODO
#}

multi method stat-for-commit(‘install’, $full-hash) {
    self.run-smth: $full-hash, {
        # ↓ scary, but works
        my $result = Rakudo::Internals.DIR-RECURSE($_).map(*.IO.s).sum ÷ 10⁶;
        $result > 10 ?? $result !! Nil
    }
}

multi method stat-for-commit(‘libmoar’, $full-hash) {
    self.run-smth: $full-hash, {
        my $file = “$_/lib/libmoar.so”.IO;
        $file.IO.e ?? $file.IO.s ÷ 10⁶ !! Nil
    }
}

multi method irc-to-me($msg where /:i ( <{OPTIONS.keys}> ) (‘0’)? /) {
    my $type   = ~$0;
    my $zeroed = ?$1;
    start {
        my ($value, %additional-files) = self.process: $msg, $type, $zeroed;
        $value.defined
        ?? ($value but $msg) but FileStore(%additional-files)
        !! Nil
    }
}

multi method process($msg, $type, $zeroed) {
    $msg.reply: ‘OK! Working on it…’;

    my @results;
    %stat-locks{$type}.protect: {
        my %data := %stats{$type};

        my $let's-save = False;

        my @git = ‘git’, ‘--git-dir’, “{RAKUDO}/.git”, ‘--work-tree’, RAKUDO;
        my @command = |@git, ‘log’, ‘-z’, ‘--pretty=%H’, RANGE;
        for run(:out, |@command).out.split: 0.chr, :skip-empty -> $full {
            next unless $full;
            #my $short = self.to-full-commit($_, :short);

            if %data{$full}:!exists and self.build-exists: $full {
                %data{$full} = self.stat-for-commit($type, $full);
                $let's-save = True
            }
            @results.push: ($full, $_) with %data{$full}
        }

        spurt “{STATS-LOCATION}/$type”, to-json %data if $let's-save;
    }

    my $pfilename = ‘plot.svg’;
    my $title = OPTIONS{$type};
    my @values = @results.reverse»[1];
    my @labels = @results.reverse»[0]».substr: 0, 8;

    my $plot = SVG::Plot.new(
        :1000width,
        :800height,
        min-y-axis => $zeroed ?? 0 !! Nil,
        :$title,
        values     => (@values,),
        :@labels,
        background => ‘white’,
    ).plot(:lines);
    my %graph = $pfilename => SVG.serialize: $plot;

    my $msg-response = @results.reverse.map(*.join: ‘ ’).join: “\n”;

    $msg-response, %graph
}

Statisfiable.new.selfrun: ‘statisfiable6’, [/stat6?/, fuzzy-nick(‘statisfiable6’, 3) ]

# vim: expandtab shiftwidth=4 ft=perl6

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
use Whateverable::Builds;
use Whateverable::Processing;
use Whateverable::Running;

use IRC::Client;

unit class Committable does Whateverable;

constant TOTAL-TIME = 60 × 10;
constant shortcuts = %(
    mc  => ‘2015.12’,      ec  => ‘2015.12’,
    mch => ‘2015.12,HEAD’, ech => ‘2015.12,HEAD’,
    ma  => ‘all’, all => ‘all’,
    what => ‘6c’, ‘6c’ => ‘6c’, ‘v6c’ => ‘6c’, ‘v6.c’ => ‘6c’, ‘6.c’ => ‘6c’,
    releases => ‘releases’,
);

# https://github.com/rakudo/rakudo/wiki/dev-env-vars
my \ENV-VARS = set <MVM_SPESH_DISABLE MVM_SPESH_BLOCKING
                    MVM_SPESH_NODELAY MVM_SPESH_INLINE_DISABLE
                    MVM_SPESH_OSR_DISABLE MVM_JIT_DISABLE>;

method help($msg) {
    “Like this: {$msg.server.current-nick}: f583f22,HEAD say ‘hello’; say ‘world’”
}

multi method irc-to-me($msg where .args[1] ~~ ?(my $prefix = m/^ $<shortcut>=@(shortcuts.keys)
                                                                 [‘:’ | ‘,’]/)
                                  && .text ~~ /^ \s* $<code>=.+ /) is default {
    my $code     = ~$<code>;
    my $shortcut = shortcuts{$prefix<shortcut>};
    start process $msg, $shortcut, $code
}

multi method irc-to-me($msg where /^ \s* [ @<envs>=((<[\w-]>+)‘=’(\S*)) ]* %% \s+
                                     $<config>=<.&commit-list> \s+
                                     $<code>=.+ /) {
    my %ENV = @<envs>.map: { ~.[0] => ~.[1] } if @<envs>;
    for %ENV {
        grumble “ENV variable {.key} is not supported” if .key ∉ ENV-VARS;
        grumble “ENV variable {.key} can only be 0, 1 or empty” if .value ne ‘0’ | ‘1’ | ‘’;
    }
    %ENV ,= %*ENV;
    my $config = ~$<config>;
    my $code   = ~$<code>;
    start process $msg, $config, $code, :%ENV

}

sub process($msg, $config is copy, $code is copy, :%ENV) {
    my $start-time = now;
    if $config ~~ /^ [say|sub] $/ {
        $msg.reply: “Seems like you forgot to specify a revision (will use “v6.c” instead of “$config”)”;
        $code = “$config $code”;
        $config = ‘v6.c’
    }
    my @commits = get-commits $config;
    my $file = process-code $code, $msg;
    LEAVE .unlink with $file;

    my @outputs; # unlike %shas this is ordered
    my %shas;    # { output => [sha, sha, …], … }

    proccess-and-group-commits @outputs, %shas, $file, @commits,
                               :intermingle, :!prepend,
                               :$start-time, time-limit => TOTAL-TIME,
                               :%ENV;

    commit-groups-to-gisted-reply @outputs, %shas, $config;
}


my %*BOT-ENV;

Committable.new.selfrun: ‘committable6’, [ / [ | c <!before [｢:\｣|｢:/｣]> [ommit]?6?
                                               | @(shortcuts.keys) ] <before ‘:’> /,
                                           fuzzy-nick(‘committable6’, 3) ]

# vim: expandtab shiftwidth=4 ft=perl6

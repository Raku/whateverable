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

unit class Greppable does Whateverable;

my \ECO-PATH = ‘all-modules’;

method help($msg) {
    “Like this: {$msg.server.current-nick}: password”
}

multi method irc-to-me($msg) {
    my $value = self.process: $msg;
    return without $value;
    return ‘Found nothing!’ unless $value;
    return $value but Reply($msg)
}

method process($msg) {
    my @git = ‘git’, ‘--git-dir’, “{ECO-PATH}/.git”, ‘--work-tree’, ECO-PATH;
    run |@git, ‘pull’;
    self.get-output(|@git, ‘grep’, ‘-i’, ‘--perl-regexp’, ‘--line-number’,
                    ‘-e’, $msg)<output>
}


if ECO-PATH.IO !~~ :d {
    run ‘git’, ‘clone’, ‘https://github.com/moritz/perl6-all-modules.git’, ECO-PATH
}

Greppable.new.selfrun: ‘greppable6’, [ /‘grep’ 6?/, fuzzy-nick(‘greppable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

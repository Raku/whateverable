#!/usr/bin/env perl6
# Copyright © 2018
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

use Misc;
use Whateverable;

use IRC::Client;
use JSON::Fast;

use Cro::HTTP::Router;
use Cro::HTTP::Server;

my $host-arch = $*KERNEL.hardware;
$host-arch = ‘amd64’|‘x86_64’ if $host-arch eq ‘amd64’|‘x86_64’;
$host-arch = $*KERNEL.name ~ ‘-’ ~ $host-arch;

my $application = route {
    get sub ($build, :$type=‘rakudo-moar’, :$arch) {
        return not-found if $arch and $arch ne $host-arch;
        my $backend = $type; # “backend” is used internally but sounds weird
        # TODO change once resolved: https://github.com/croservices/cro-http/issues/21
        return bad-request unless $backend ~~ <rakudo-moar moarvm>.any;
        my $repo = $backend eq ‘rakudo-moar’ ?? $RAKUDO !! MOARVM;
        my $full-commit = to-full-commit $build, :$repo;
        return not-found unless $full-commit;
        return not-found unless build-exists $full-commit, :$backend;

        my $archive-path  = “{ARCHIVES-LOCATION}/$backend/$full-commit.zst”;
        my $archive-link  = “{ARCHIVES-LOCATION}/$backend/$full-commit”;

        my $file = $archive-path.IO.e ?? $archive-path !! $archive-link.IO.resolve.Str;
        header ‘Content-Disposition’, “attachment; filename="{$file.IO.basename}"”;
        static $file
    }
}

my Cro::Service $share = Cro::HTTP::Server.new:
    :host<localhost>, :port<42434>, :$application;
$share.start; # TODO handle exceptions

unit class Shareable does Whateverable;

method help($msg) {
    “Like this: {$msg.server.current-nick}: f583f22”
}

multi method irc-to-me($msg where /^ $<build>=[\S+] $/) {
    my $full-commit = to-full-commit ~$<build>;
    return ‘No build for this commit’ unless build-exists $full-commit;
    “https://whateverable.6lang.org/$<build>”
}

Shareable.new.selfrun: ‘shareable6’, [ fuzzy-nick(‘shareable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

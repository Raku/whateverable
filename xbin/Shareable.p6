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

use Whateverable;
use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Config;
use Whateverable::Running;

use Cro::HTTP::Router;
use Cro::HTTP::Server;
use IRC::Client;
use JSON::Fast;

#my $host-arch = $*KERNEL.hardware;
my $host-arch = ‘x86_64’;
$host-arch = ‘amd64’|‘x86_64’ if $host-arch eq ‘amd64’|‘x86_64’;
#$host-arch = $*KERNEL.name ~ ‘-’ ~ $host-arch;
$host-arch = ‘linux’ ~ ‘-’ ~ $host-arch;

sub cached-archive($build where ‘HEAD.tar.gz’, :$backend=‘rakudo-moar’, :$arch) {
    my $repo = $backend eq ‘rakudo-moar’ ?? $CONFIG<rakudo> !! $CONFIG<moarvm>;
    my $full-commit = to-full-commit ‘HEAD’, :$repo; # TODO that's slightly repetitive
    my $file = “/tmp/whateverable/shareable/$backend/$full-commit.tar.gz”.IO;
    if not $file.e {
        run-smth :$backend, $full-commit, sub ($build-path) {
            # can only be in this block once because
            # it locks on the build while it's used
            return if $file.e;
            mkdir $file.IO.parent; # for the first run
            .unlink for $file.IO.parent.dir; # TODO any way to be more selective?
            my $proc = run <tar --create --gzip --absolute-names --file>, $file, ‘--’, $build-path;
            # TODO what if it failed? Can it fail?
            # TODO Some race-ness is still not handled
        }
    }
    header ‘Content-Disposition’, “attachment; filename="{$file.IO.basename}"”;
    static ~$file
}

my $application = route {
    get sub () { redirect :temporary, ‘https://github.com/perl6/whateverable’ }
    get sub ($build, :$type=‘rakudo-moar’, :$arch) {
        return not-found if $arch and $arch ne $host-arch;
        my $backend = $type; # “backend” is used internally but sounds weird
        # TODO change once resolved: https://github.com/croservices/cro-http/issues/21
        return bad-request unless $backend ~~ <rakudo-moar moarvm>.any;
        return cached-archive $build, :$backend, :$arch if $build eq ‘HEAD.tar.gz’;
        my $repo = $backend eq ‘rakudo-moar’ ?? $CONFIG<rakudo> !! $CONFIG<moarvm>;
        my $full-commit = to-full-commit $build, :$repo;
        return not-found unless $full-commit;
        return not-found unless build-exists $full-commit, :$backend;

        my $archive-path  = “$CONFIG<archives-location>/$backend/$full-commit.zst”;
        my $archive-link  = “$CONFIG<archives-location>/$backend/$full-commit”;

        my $file = $archive-path.IO.e ?? $archive-path !! $archive-link.IO.resolve.Str;
        header ‘Content-Disposition’, “attachment; filename="{$file.IO.basename}"”;
        static $file
    }
}

ensure-config;
my Cro::Service $share = Cro::HTTP::Server.new: :$application,
    :host($CONFIG<shareable><host>), :port($CONFIG<shareable><port>);
$share.start; # TODO handle exceptions

unit class Shareable does Whateverable;

method help($msg) {
    “Like this: {$msg.server.current-nick}: f583f22”
}

multi method irc-to-me($msg where /^ $<build>=[\S+] $/) {
    my $full-commit = to-full-commit ~$<build>;
    return ‘No build for this commit’ unless build-exists $full-commit;
    my $link = $CONFIG<mothership> // $*CONFIG<self>;
    “$link/$<build>”
}


my %*BOT-ENV;

Shareable.new.selfrun: ‘shareable6’, [ fuzzy-nick(‘shareable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

#!/usr/bin/env perl6
# Copyright © 2017-2020
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
use Whateverable::Config;

use File::Directory::Tree;
use IRC::Client;

unit class Buildable does Whateverable;

my $CHANNEL = %*ENV<DEBUGGABLE> ?? ‘#whateverable’ !! ‘#raku-dev’;

enum Project <rakudo-moar moarvm>; # rakudo-jvm rakudo-js # TODO extract it
my \DIR-BASE          = PROJECT.lc;
my \BUILDS-LOCATION   = “/tmp/whateverable/{DIR-BASE}”;
my \ARCHIVES-LOCATION = “{WORKING-DIRECTORY}/data/builds/{DIR-BASE}”.IO.absolute;
my \REPO-LATEST       = “/tmp/whateverable/{DIR-BASE}-repo”;
my \CUTOFF-DATE       = PROJECT == MoarVM ?? ‘2018-10-01’ !! ‘2018-02-01’;
my \TAGS-SINCE        = ‘2014-01-01’;

sub pack-all() {
    my @git-latest = ‘git’, ‘--git-dir’, “{REPO-LATEST}/.git”, ‘--work-tree’, REPO-LATEST;
    my @args-tags  = |@git-latest, ‘log’, ‘-z’, ‘--pretty=%H’, ‘--tags’, ‘--no-walk’, ‘--since’, TAGS-SINCE;
    my @args       = |@git-latest, ‘log’, ‘-z’, ‘--pretty=%H’, ‘--all’, ‘--before’, CUTOFF-DATE, ‘--reverse’;

    my %ignore;
    for run(:out, |@args-tags).out.split(0.chr, :skip-empty) {
        %ignore{$_}++;
    }

    my @pack;
    for run(:out, |@args).out.split(0.chr, :skip-empty) {
        next if %ignore{$_}:exists; # skip tags
        next unless “{ARCHIVES-LOCATION}/$_.tar.zst”.IO ~~ :e;
        @pack.push: $_;
        if @pack == 20 {
            pack-it @pack;
            @pack = ();
        }
    }
}

sub pack-it(@pack) {
    my @paths;
    for @pack {
        my $archive-path = “{ARCHIVES-LOCATION}/$_.tar.zst”;
        my $build-path = “{BUILDS-LOCATION}/$_”;
        @paths.push: $build-path;

        # TODO Of course it should lock on the directory like everything else does.
        #      The reason why we get away with this is because we run this script
        #      once in forever.
        my $proc = run :out, :bin, <pzstd -dqc -->, $archive-path;
        exit 1 unless run :in($proc.out), :bin, <tar x --absolute-names>;
    }

    my @bytes = @pack.join.comb(2)».parse-base: 16;
    my $sha-proc = run :out, :in, :bin, <sha256sum -b>;
    $sha-proc.in.write: Blob.new(@bytes);
    $sha-proc.in.close;
    my $sha = $sha-proc.out.slurp(:close).decode.words.head; # could also be a random name, doesn't matter
    exit 1 unless $sha;
    my $large-archive-path = “{ARCHIVES-LOCATION}/$sha.tar.lrz”;

    my $proc = run :out, :bin, <tar cf - --absolute-names --remove-files -->, |@paths;
    if $large-archive-path.IO.e {
        $large-archive-path.IO.unlink # remove existing (just in case)
    }
    if run :in($proc.out), :bin, <lrzip -q -L 9 -o>, $large-archive-path {
        for @pack {
            if “{ARCHIVES-LOCATION}/$_”.IO.e {
                “{ARCHIVES-LOCATION}/$_”.IO.unlink # remove existing (just in case)
            }
            $large-archive-path.IO.symlink(“{ARCHIVES-LOCATION}/$_”);
            unlink “{ARCHIVES-LOCATION}/$_.tar.zst”
        }
    }
}

multi method keep-building($msg) {
    # TODO multi-server setup not supported (this will be irrelevant after #284)
    ensure-config;
    my $channel = listen-to-webhooks …;

    sleep 60 × 5; # let other bots start up and stuff
    react {
        whenever $channel {
            # build-all
        }
        whenever Supply.interval: 60 × 30 {
            # build-all
        }
        whenever Supply.interval: 60 × 60 {
            pack-all
        }
    }

    CATCH { default { self.handle-exception: $_, $msg } }
}

multi method irc-connected($msg) {
    once start self.keep-building: $msg
}


Buildable.new.selfrun: ‘buildable6’, [ / build[s]?6? <before ‘:’> /,
                                       fuzzy-nick(‘buildable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

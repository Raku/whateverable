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

use Whateverable::Config;

unit module Whateverable::Building;

enum Project <rakudo-moar moarvm rakudo-jvm rakudo-js>;

sub latest-repo($project = $*PROJECT) { “$*TMPDIR/whateverable/{$project}-repo”.IO }
sub get-commits(*@args) {
    run(:cwd(latest-repo $*PROJECT), :out, <git log -z --pretty=%H>, |@args)
    .out.split(0.chr, :skip-empty)
}
my $TAGS-SINCE        = ‘2014-01-01’;     # to build all tags
my $EVERYTHING-RANGE  = ‘2014.01^..HEAD’; # to build everything
my $ALL-SINCE         = ‘2017-01-01’;     # to catch branches that are flapping in the breeze
sub get-commits-tags()   { get-commits |<--tags --no-walk --since>, $TAGS-SINCE }
sub get-commits-master() { get-commits $EVERYTHING-RANGE } # slap --reverse here to build in historical order
sub get-commits-all()    { get-commits |<--all --since>, $ALL-SINCE }
sub get-commits-new()    { get-commits |<--all --since>, Date.today.earlier(:6month).first-date-in-month }

sub ensure-latest-git-repo() {
    # ↓ Yes, separate cloned repo for every project.
    my $REPO-LATEST = latest-repo;

    if $REPO-LATEST.IO ~~ :d  {
        run :cwd($REPO-LATEST), <git pull>;
    } else {
        exit unless run <git clone -->, $CONFIG<projects>{$*PROJECT}<repo-origin>, $REPO-LATEST;
    }
}

#| Goes through all commits and attempts to create builds
sub build-all-commits($project) is export {
    my $*PROJECT = $project;
    ensure-latest-git-repo;

    my $new-builds = 0;
    for flat(get-commits-tags, get-commits-master, get-commits-all).unique {
        # Please don't waste your time trying to parallelize this.
        # It's not worth it. I tried. Just wait.
        $new-builds++ if process-commit $project, $_;

        # When working too hard it's important to take a break, let things
        # settle. Otherwise with a large backlog the bots may be behind origin's
        # HEAD for days, and that's not very useful. So the idea here is that we
        # build a few tens of builds, and then pull the latest repo state as if
        # everything is finished. The idea is that the latest commits now have
        # builds, but older commits may have gaps, and that's OK! All bots
        # handle missing builds for older commits properly.
        last if $new-builds > 20;
    }

    # update repo so that bots know about latest commits
    run :cwd($CONFIG<projects>{$project}<repo-path>), <git pull --tags>;
    run :cwd($CONFIG<projects>{$project}<repo-path>), <git fetch --all>;
}

#| Repacks existing builds in order to save space
sub pack-all-builds($project) is export {
    my $*PROJECT = $project;
    my %ignore;
    %ignore{$_}++ for flat(get-commits-tags, get-commits-new);

    my @pack;
    for get-commits-all() {
        next if %ignore{$_}:exists; # skip tags
        next unless “{$CONFIG<projects>{$project}<archives-path>}/$_.tar.zst”.IO ~~ :e;
        @pack.push: $_;
        if @pack == 20 {
            pack-it $project, @pack;
            @pack = ();
        }
    }
}

sub get-build-revision($repo, $on-commit, $file) {
    run(:cwd($repo), :out, <git show>,
        “{$on-commit}:tools/build/$file”).out.slurp-rest.trim
}

sub process-commit($project, $commit) is export {
    my $project-config = $CONFIG<projects>{$project};
    my $archive-path = $project-config<archives-path>
                       .IO.add(“$commit.tar.zst”).absolute.IO;
    return False if $archive-path ~~ :e; # already exists
    return False if $project-config<archives-path>
                       .IO.add(“$commit”).absolute.IO ~~ :e; # already exists in long-term storage

    my $BUILDS-LOCATION = “$*TMPDIR/whateverable/{$project}”.IO;
    mkdir $BUILDS-LOCATION;

    use File::Temp;
    my ($temp-folder,) = tempdir, :!unlink;
    my $build-path   = $BUILDS-LOCATION.add($commit).absolute;
    my $log-path     = $build-path;

    # ⚡ clone
    run <git clone -q -->, latest-repo($project), $temp-folder;
    # ⚡ checkout to $commit
    run :cwd($temp-folder), <git reset -q --hard>, $commit;

    # No :merge for log files because RT#125756 RT#128594

    my $config-ok;
    mkdir $build-path;
    {
        # ⚡ configure
        my $old-dir = $*CWD;
        LEAVE chdir $old-dir;
        chdir $temp-folder;
        say “»»»»» $commit: configure”;
        my $configure-log-fh = open :w, “$log-path/configure.log”;
        my $configure-err-fh = open :w, “$log-path/configure.err”;

        my @args;
        given $project {
            when ‘moarvm’ {
                @args = |<perl -- Configure.pl>, “--prefix=$build-path”,
                              ‘--debug=3’;
            }
            default { # assume Rakudo
                @args = |<perl -- Configure.pl>, “--prefix=$build-path”,
                              |<--gen-moar --gen-nqp --backends=moar>;
                my $GIT-REFERENCE = ‘./data’.IO.absolute;
                if run <grep -m1 -q -- --git-reference Configure.pl> {
                    @args.push: “--git-reference=$GIT-REFERENCE”
                }
            }
        }

        $config-ok = run :out($configure-log-fh), :err($configure-err-fh), |@args;

        $configure-log-fh.close;
        $configure-err-fh.close;
        say “»»»»» Cannot configure $commit” unless $config-ok;
    }

    my $make-ok;
    if $config-ok {
        # ⚡ make
        say “»»»»» $commit: make”;
        my $make-log-fh = open :w, “$log-path/make.log”;
        my $make-err-fh = open :w, “$log-path/make.err”;
        my @args = do given $project {
            when ‘moarvm’      { |<make -j 7 -C>, $temp-folder }
            when ‘rakudo-moar’ { |<make      -C>, $temp-folder }
        }
        $make-ok = run :out($make-log-fh), :err($make-err-fh), @args;
        $make-log-fh.close;
        $make-err-fh.close;
        say “»»»»» Cannot make $commit” unless $make-ok;
    }
    if $make-ok {
        # ⚡ make install
        say “»»»»» $commit: make install”;
        my $install-log-fh = open :w, “$log-path/make-install.log”;
        my $install-err-fh = open :w, “$log-path/make-install.err”;
        my $install-ok = run(:out($install-log-fh), :err($install-err-fh),
                             <make -C>, $temp-folder, ‘install’);
        $install-log-fh.close;
        $install-err-fh.close;
        say “»»»»» Cannot install $commit” unless $install-ok;
    }

    # ⚡ compress
    # No matter what we got, compress it
    say “»»»»» $commit: compressing”;
    my $proc = run(:out, :bin, <tar cf - --absolute-names --remove-files -->, $build-path);
    run(:in($proc.out), :bin, <zstd -c -19 -q -o>, $archive-path);

    use File::Directory::Tree;
    rmtree $temp-folder;

    return True
}

sub pack-it($project, @pack) {
    my $archives-path = $CONFIG<projects>{$project}<archives-path>;
    my @paths;
    for @pack {
        my $archive-path = “$archives-path/$_.tar.zst”;
        my $BUILDS-LOCATION = “$*TMPDIR/whateverable/{$project}”.IO;
        my $build-path = “$BUILDS-LOCATION/$_”;
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
    my $large-archive-path = “$archives-path/$sha.tar.lrz”;

    my $proc = run :out, :bin, <tar cf - --absolute-names --remove-files -->, |@paths;
    if $large-archive-path.IO.e {
        $large-archive-path.IO.unlink # remove existing (just in case)
    }
    if run :in($proc.out), :bin, <lrzip -q -L 9 -o>, $large-archive-path {
        for @pack {
            if “$archives-path/$_”.IO.e {
                “$archives-path/$_”.IO.unlink # remove existing (just in case)
            }
            $large-archive-path.IO.symlink(“$archives-path/$_”);
            unlink “$archives-path/$_.tar.zst”
        }
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

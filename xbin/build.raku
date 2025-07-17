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

# This script will build something for all commits that it can find

use File::Temp:ver<0.0.11+>:auth<zef:raku-community-modules>;
use File::Directory::Tree:ver<0.1+>:auth<zef:labster>;

enum Project <Rakudo-Moar Rakudo-JVM Rakudo-JS MoarVM>;
my \PROJECT = do given @*ARGS[0] // ‘’ {
    when /:i ^‘moarvm’$ / { MoarVM }
    default { Rakudo-Moar }
}
my \RAKUDOISH         = PROJECT == Rakudo-Moar | Rakudo-JVM | Rakudo-JS;
my \DIR-BASE          = PROJECT.lc;

my \PARALLEL-COUNT    = 1;
my \TAGS-SINCE        = ‘2014-01-01’;     # to build all tags
my \COMMIT-RANGE      = ‘2015.07^..HEAD’; # to build recent commits
my \ALL-SINCE         = ‘2017-01-01’;     # to catch branches that are flapping in the breeze
my \EVERYTHING-RANGE  = ‘2014.01^..HEAD’; # to build everything, but in historical order

my \WORKING-DIRECTORY = ‘.’; # TODO not supported yet

my \RAKUDO-NQP-ORIGIN = ‘https://github.com/perl6/nqp.git’;
my \RAKUDO-NQP-LATEST = “/tmp/whateverable/rakudo-triple-nqp-repo”;
my \RAKUDO-MOAR-ORIGIN = ‘https://github.com/MoarVM/MoarVM.git’;
my \RAKUDO-MOAR-LATEST = “/tmp/whateverable/rakudo-triple-moar-repo”;
my \REPO-ORIGIN       = RAKUDOISH
                        ?? ‘https://github.com/rakudo/rakudo.git’
                        !! ‘https://github.com/MoarVM/MoarVM.git’;

my \REPO-LATEST       = “/tmp/whateverable/{DIR-BASE}-repo”;
# ↑ yes, separate cloned repo for every backend to prevent several
#   instances of this script fighting with each other
my \REPO-CURRENT      = “{WORKING-DIRECTORY}/data/{DIR-BASE}”.IO.absolute;

my \ARCHIVES-LOCATION = “{WORKING-DIRECTORY}/data/builds/{DIR-BASE}”.IO.absolute;
my \BUILDS-LOCATION   = “/tmp/whateverable/{DIR-BASE}”;
my \BUILD-LOCK        = “{BUILDS-LOCATION}/build-lock”;

my \GIT-REFERENCE     = “{WORKING-DIRECTORY}/data”.IO.absolute;

mkdir BUILDS-LOCATION;
mkdir ARCHIVES-LOCATION;

# TODO IO::Handle.lock ? run ‘flock’? P5 modules?
exit 0 unless run :err(Nil), <mkdir -->, BUILD-LOCK; # only one instance running
my $locked = True;
END BUILD-LOCK.IO.rmdir if $locked;

sub pull-or-clone($repo-origin, $repo-path) {
    if $repo-path.IO ~~ :d  {
        my $old-dir = $*CWD;
        run :cwd($repo-path), <git pull>;
    } else {
        exit unless run <git clone -->, $repo-origin, $repo-path;
    }
}

pull-or-clone REPO-ORIGIN, REPO-LATEST;
if RAKUDOISH {
    pull-or-clone RAKUDO-NQP-ORIGIN,  RAKUDO-NQP-LATEST;
    pull-or-clone RAKUDO-MOAR-ORIGIN, RAKUDO-MOAR-LATEST;
}

if REPO-CURRENT.IO !~~ :d  {
    run <git clone --origin local-origin -->, REPO-LATEST, REPO-CURRENT;
    # make sure we can still pull branch info and other stuff from the actual origin
    run :cwd(REPO-CURRENT), <git remote add origin>, REPO-ORIGIN;
}

my $channel = Channel.new;

my @git-log     = <git log -z --pretty=%H>;
my @args-tags   = |@git-log, |<--tags --no-walk --since>, TAGS-SINCE;
my @args-latest = |@git-log, COMMIT-RANGE;
my @args-recent = |@git-log, |<--all --since>, ALL-SINCE;
my @args-old    = |@git-log, ‘--reverse’, EVERYTHING-RANGE;

my %commits;

# Normal Rakudo commits
for @args-tags, @args-latest, @args-recent, @args-old -> @_ {
    for run(:cwd(REPO-LATEST), :out, |@_).out.split(0.chr, :skip-empty) {
        next if %commits{$_}:exists;
        %commits{$_}++;
        $channel.send: $_
    }
}

sub get-build-revision($repo, $on-commit, $file) {
    run(:cwd($repo), :out, ‘git’, ‘show’,
        “{$on-commit}:tools/build/$file”).out.slurp-rest.trim
}

# Rakudo-NQP-Moar triples (for bumps)
#`｢｢｢
if PROJECT == Rakudo-Moar {
    my @args-bumps = ‘git’, ‘log’, ‘-z’, ‘--pretty=%x00%H’,
                     ‘--follow’, ‘--reverse’,
                     EVERYTHING-RANGE, ‘tools/build/NQP_REVISION’;
    for run(:cwd(REPO-LATEST), :out, |@args-bumps)
      .out.split(0.chr, :skip-empty).rotor(2) -> ($rakudo-sha, $diff) {
        #my $nqp-old = get-build-revision REPO-LATEST, “$rakudo-sha^”, ‘NQP_REVISION’;
        #my $nqp-new = get-build-revision REPO-LATEST, “$rakudo-sha”,  ‘NQP_REVISION’;

        #say “$rakudo-sha”;
        for run(:cwd(RAKUDO-NQP-LATEST), :out, |@git-log, “$nqp-old..$nqp-new”)
          .out.split(0.chr, :skip-empty) -> $nqp-sha {
            my $moar-sha = get-build-revision RAKUDO-NQP-LATEST, “$nqp-sha”, ‘MOAR_REVISION’;
            # TODO shas are not shas
            say “|- $nqp-sha - $moar-sha”;
        }
        for run(:cwd(RAKUDO-NQP-LATEST), :out, |@git-log, ‘--follow’, ‘--reverse’,
                “$nqp-old..$nqp-new”, ‘tools/build/MOAR_REVISION’)
          .out.split(0.chr, :skip-empty) -> $nqp-sha {
            my $moar-old = get-build-revision RAKUDO-NQP-LATEST, “$nqp-sha^”, ‘MOAR_REVISION’;
            my $moar-new = get-build-revision RAKUDO-NQP-LATEST, “$nqp-sha”,  ‘MOAR_REVISION’;
            for run(:cwd(RAKUDO-MOAR-LATEST), :out, |@git-log, “$moar-old..$moar-new”)
              .out.split(0.chr, :skip-empty) -> $moar-sha {
                say “   |- $moar-sha”;
            }
        }
    }
}
# ｣｣｣


await (for ^PARALLEL-COUNT { # TODO rewrite when .race starts working in rakudo
              start loop {
                  my $commit = $channel.poll;
                  last unless $commit;
                  try { process-commit($commit) }
              }
          });

# update repo so that bots know about latest commits
run :cwd(REPO-CURRENT), <git pull --tags>, REPO-LATEST;
run :cwd(REPO-CURRENT), <git fetch --all>;

sub process-commit($commit) {
    return if “{ARCHIVES-LOCATION}/$commit.zst”.IO ~~ :e; # already exists
    return if “{ARCHIVES-LOCATION}/$commit”.IO     ~~ :e; # already exists (long-term storage)
    return if $++ ≥ 10; # refuse to build too many commits at once

    my ($temp-folder,) = tempdir, :!unlink;
    my $build-path   = “{BUILDS-LOCATION}/$commit”.IO.absolute;
    my $log-path     = $build-path;
    my $archive-path = “{ARCHIVES-LOCATION}/$commit.zst”.IO.absolute;

    # ⚡ clone
    run <git clone -q -->, REPO-LATEST, $temp-folder;
    # ⚡ checkout to $commit
    run :cwd($temp-folder), <git reset -q --hard>, $commit;

    # No :merge for log files because RT #125756 RT #128594

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

        my @args = do given PROJECT {
            when MoarVM {
                |<perl -- Configure.pl>, “--prefix=$build-path”,
                     ‘--debug=3’
            }
            when Rakudo-Moar {
                |<perl -- Configure.pl>, “--prefix=$build-path”,
                     |<--gen-moar --gen-nqp --backends=moar>
            }
        }
        if PROJECT == Rakudo-Moar
        and run <grep -m1 -q -- --git-reference Configure.pl> {
            @args.push: “--git-reference={GIT-REFERENCE}”
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
        my @args = do given PROJECT {
            when MoarVM      { |<make -j 7 -C>, $temp-folder }
            when Rakudo-Moar { |<make      -C>, $temp-folder }
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

    rmtree $temp-folder;
}

# vim: expandtab shiftwidth=4 ft=perl6

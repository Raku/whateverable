#!/usr/bin/env perl6

# This script will build rakudo for all commits that it can find

use File::Temp;
use File::Directory::Tree;

constant PARALLEL-COUNT    = 7;
constant COMMIT-RANGE      = ‘2015.10^..HEAD’;

constant WORKING-DIRECTORY = ‘.’; # TODO not supported yet

constant RAKUDO-ORIGIN     = ‘https://github.com/rakudo/rakudo.git’;
constant RAKUDO-LATEST     = ‘/tmp/whateverable/rakudo-repo’;
constant RAKUDO-CURRENT    = “{WORKING-DIRECTORY}/rakudo”.IO.absolute;

constant ARCHIVES-LOCATION = “{WORKING-DIRECTORY}/builds/rakudo-moar”.IO.absolute;
constant BUILDS-LOCATION   = ‘/tmp/whateverable/rakudo-moar’;
constant BUILD-LOCK        = ‘/tmp/whateverable/build-lock’;

constant LEGACY-BUILDS-LOCATION = “{WORKING-DIRECTORY}/builds”.IO.absolute;

mkdir BUILDS-LOCATION;
mkdir ARCHIVES-LOCATION;

# TODO IO::Handle.lock ? run ‘flock’? P5 modules?
exit 0 unless run ‘mkdir’, ‘--’, BUILD-LOCK; # only one instance running
my $locked = True;
END BUILD-LOCK.IO.rmdir if $locked;

if RAKUDO-LATEST.IO ~~ :d  {
    my $old-dir = $*CWD;
    LEAVE chdir $old-dir;
    chdir RAKUDO-LATEST;
    run ‘git’, ‘pull’;
} else {
    exit unless run ‘git’, ‘clone’, ‘--’, RAKUDO-ORIGIN, RAKUDO-LATEST;
}

if RAKUDO-CURRENT.IO !~~ :d  {
    run ‘git’, ‘clone’, ‘--’, RAKUDO-LATEST, RAKUDO-CURRENT;
}

my $channel = Channel.new;

my @git-latest = ‘git’, ‘--git-dir’, “{RAKUDO-LATEST}/.git”, ‘--work-tree’, RAKUDO-LATEST;
for run(:out, |@git-latest, ‘log’, ‘-z’, ‘--pretty=%H’, COMMIT-RANGE).out.split(0.chr, :skip-empty) {
    $channel.send: $_
}

await (for ^PARALLEL-COUNT { # TODO rewrite when .race starts working in rakudo
              start loop {
                  my $commit = $channel.poll;
                  last unless $commit;
                  process-commit($commit);
              }
          });

# update rakudo repo so that bots know about latest commits
run ‘git’, ‘--git-dir’, “{RAKUDO-CURRENT}/.git”, ‘--work-tree’, RAKUDO-CURRENT, ‘pull’, RAKUDO-LATEST;

sub process-commit($commit) {
    return if “{ARCHIVES-LOCATION}/$commit.zstd”.IO ~~ :e; # already exists

    my ($temp-folder, $fh-unlink-on-destroy) = tempdir :unlink;
    my $build-path   = “{BUILDS-LOCATION}/$commit”.IO.absolute;
    my $log-path     = $build-path;
    my $archive-path = “{ARCHIVES-LOCATION}/$commit.zst”.IO.absolute;

    # ⚡ clone
    run ‘git’, ‘clone’, ‘-q’, ‘--’, RAKUDO-LATEST, $temp-folder;
    # ⚡ checkout to $commit
    my @git-temp = ‘git’, ‘--git-dir’, “$temp-folder/.git”, ‘--work-tree’, $temp-folder;
    run |@git-temp, ‘reset’, ‘-q’, ‘--hard’, $commit;

    # No :merge for log files because RT #125756 RT #128594

    mkdir $build-path;
    {
        # ⚡ configure
        my $old-dir = $*CWD;
        LEAVE chdir $old-dir;
        chdir $temp-folder;
        say “»»»»» $commit: configure”;
        my $configure-log-fh = open :w, “$log-path/configure.log”;
        run(:out($configure-log-fh), :err(Nil), ‘perl’, ‘--’, ‘Configure.pl’,
            ‘--gen-moar’, ‘--gen-nqp’, ‘--backends=moar’, “--prefix=$build-path”);
        $configure-log-fh.close;
    }

    # ⚡ make
    say “»»»»» $commit: make”;
    my $make-log-fh = open :w, “$log-path/make.log”;
    run(:out($make-log-fh), :err(Nil), ‘make’, ‘-C’, $temp-folder);
    $make-log-fh.close;
    # ⚡ make install
    say “»»»»» $commit: make install”;
    my $install-log-fh = open :w, “$log-path/make-install.log”;
    run(:out($install-log-fh), :err(Nil), ‘make’, ‘-C’, $temp-folder, ‘install’);
    $install-log-fh.close;

    # ⚡ compress
    say “»»»»» $commit: compressing”;
    my $proc = run(:out, :bin, ‘tar’, ‘cf’, ‘-’, ‘--absolute-names’, ‘--remove-files’, ‘--’, $build-path);
    run(:in($proc.out), :bin, ‘zstd’, ‘-c’, ‘-19’, ‘-q’, ‘-o’, $archive-path);

    # delete old builds. TODO remove next line after transition
    rmtree “{LEGACY-BUILDS-LOCATION}/$commit”
}

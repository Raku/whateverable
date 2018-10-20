# Copyright © 2016-2018
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

use File::Directory::Tree;

use Whateverable::Config;
use Whateverable::Heartbeat;
use Whateverable::Bits;
use Whateverable::Output;
use Whateverable::Builds;

unit module Whateverable::Running;

#↓ Unpacks a build, runs $code and cleans up.
sub run-smth($full-commit-hash, Code $code,
             :$backend=‘rakudo-moar’, :$wipe = True) is export {
    my $build-path    = run-smth-build-path $full-commit-hash, :$backend;
    my $archive-path  = “$CONFIG<archives-location>/$backend/$full-commit-hash.zst”;
    my $archive-link  = “$CONFIG<archives-location>/$backend/$full-commit-hash”;

    # create all parent directories just in case
    # (may be needed for isolated /tmp)
    mkdir $build-path.IO.parent;

    # lock on the destination directory to make
    # sure that other bots will not get in our way.
    while run(:err(Nil), ‘mkdir’, ‘--’, $build-path).exitcode ≠ 0 {
        test-delay if %*ENV<TESTABLE>;
        note “$build-path is locked. Waiting…”;
        sleep 0.5 # should never happen if configured correctly (kinda)
    }
    my $proc1;
    my $proc2;
    if $archive-path.IO ~~ :e {
        if run :err(Nil), <pzstd --version> { # check that pzstd is available
            $proc1 = run :out, :bin, <pzstd --decompress --quiet --stdout -->, $archive-path;
            $proc2 = run :in($proc1.out), :bin, <tar --extract --absolute-names>;
        } else {
            die ‘zstd is not installed’ unless run :out(Nil), <unzstd --version>;
            # OK we are using zstd from the Mesozoic Era
            $proc1 = run :out, :bin, <unzstd -qc -->, $archive-path;
            $proc2 = run :in($proc1.out), :bin, <tar --extract --absolute-names>;
        }
    } else {
        die ‘lrzip is not installed’ unless run :err(Nil), <lrzip --version>; # check that lrzip is available
        $proc1 = run :out, :bin, <lrzip --decompress --quiet --outfile - -->, $archive-link;
        $proc2 = run :in($proc1.out), :bin, <tar --extract --absolute-names -->, $build-path;
    }

    if not $proc1 or not $proc2 {
        note “Broken archive for $full-commit-hash, removing…”;
        try unlink $archive-path;
        try unlink $archive-link;
        rmtree $build-path;
        return %(output => ‘Broken archive’, exit-code => -1, signal => -1, time => -1,)
    }

    my $return = $code($build-path); # basically, we wrap around $code
    rmtree $build-path if $wipe;
    $return
}

#| Returns path to the unpacked build. This is useful if you want to
#| use some build multiple times simultaneously (just pass that path
#| to the code block).
sub run-smth-build-path($full-commit-hash, :$backend=‘rakudo-moar’) is export {
    “$CONFIG<builds-location>/$backend/$full-commit-hash”;
}


sub run-snippet($full-commit-hash, $file,
                :$backend=‘rakudo-moar’,
                :@args=Empty,
                :$timeout=%*BOT-ENV<timeout> // 10,
                :$stdin=$CONFIG<stdin>,
                :$ENV) is export {
    run-smth :$backend, $full-commit-hash, -> $path {
        my $binary-path = $path.IO.add: ‘bin/perl6’;
        my %tweaked-env = $ENV // %*ENV;
        %tweaked-env<PATH> = join ‘:’, $binary-path.parent, (%tweaked-env<PATH> // Empty);
        %tweaked-env<PERL6LIB> = ‘sandbox/lib’;
        $binary-path.IO !~~ :e
        ?? %(output => ‘Commit exists, but a perl6 executable could not be built for it’,
             exit-code => -1, signal => -1, time => -1,)
        !! get-output $binary-path, |@args,
                      ‘--’, $file, :$stdin, :$timeout, ENV => %tweaked-env, :!chomp
    }
}

#↓ Greps through text using a perl6 snippet.
sub perl6-grep($stdin, $regex is copy, :$timeout = 180, :$complex = False, :$hack = 0) is export {
    my $full-commit = to-full-commit ‘HEAD’ ~ (‘^’ x $hack);
    die “No build for $full-commit. Oops!” unless build-exists $full-commit;
    $regex = “m⦑ $regex ⦒”;
    # TODO can we do something smarter?
    my $sep   = $complex ?? ｢“\0\0”｣ !! ｢“\0”｣;
    my $magic = “INIT \$*ARGFILES.nl-in = $sep; INIT \$*OUT.nl-out = $sep;”
              ~ ｢use nqp;｣
              ~ ｢ next unless｣
              ~ ($complex ?? ｢ nqp::substr($_, 0, nqp::index($_, “\0”)) ~~｣ !! ‘’) ~ “\n”
              ~ $regex ~ “;\n”
              ~ ｢last if $++ > ｣ ~ $CONFIG<gist-limit>;
    my $file = write-code $magic;
    LEAVE unlink $_ with $file;
    my $result = run-snippet $full-commit, $file, :$timeout, :$stdin, args => (‘-np’,);
    my $output = $result<output>;
    # numbers less than zero indicate other weird failures ↓
    grumble “Something went wrong ($output)” if $result<signal> < 0;

    $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
    $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0;
    grumble $output if $result<exit-code> ≠ 0 or $result<signal> ≠ 0;
    my @elems = $output.split: ($complex ?? “\0\0” !! “\0”), :skip-empty;
    if @elems > $CONFIG<gist-limit> {
        grumble “Cowardly refusing to gist more than $CONFIG<gist-limit> lines”
    }
    @elems
}

# vim: expandtab shiftwidth=4 ft=perl6

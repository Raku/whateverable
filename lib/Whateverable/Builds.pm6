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

use HTTP::UserAgent;

use Whateverable::Bits;
use Whateverable::Config;
use Whateverable::Heartbeat;
use Whateverable::Output;

unit module Whateverable::Builds;

#↓ Clones Rakudo and Moar repos and ensures some directory structure.
sub ensure-cloned-repos is export {
    # TODO racing (calling this too often when nothing is cloned yet)
    if $CONFIG<repo-current-rakudo-moar>.IO !~~ :d  {
        run <git clone -->, $CONFIG<repo-origin-rakudo>,
                            $CONFIG<repo-current-rakudo-moar>;
    }
    if $CONFIG<repo-current-moarvm>     .IO !~~ :d  {
        run <git clone -->, $CONFIG<repo-origin-moarvm>,
                            $CONFIG<repo-current-moarvm>;
    }
    mkdir “$CONFIG<archives-location>/rakudo-moar”;
    mkdir “$CONFIG<archives-location>/moarvm”;
    True
}

#↓ Runs &ensure-cloned-repos to clone Rakudo and Moar repos if
#↓ necessary and then pulls. It is recommended to run this before
#↓ doing anything.
sub pull-cloned-repos is export {
    ensure-cloned-repos;
    run :cwd($CONFIG<repo-current-rakudo-moar>), <git pull>;
    run :cwd($CONFIG<repo-current-moarvm     >), <git pull>;
    True
}

#↓ Quick and dirty way to get a short representation of some commit.
sub get-short-commit($original-commit) is export { # TODO proper solution please
    $original-commit ~~ /^ <xdigit> ** 7..40 $/
    ?? $original-commit.substr(0, 7)
    !! $original-commit
}


#↓ Turns anything into a full SHA (returns Nil if can't).
sub to-full-commit($commit, :$short=False, :$repo=$CONFIG<rakudo>) is export {
    return if run(:out(Nil), :err(Nil), :cwd($repo),
                  <git rev-parse --verify>, $commit).exitcode ≠ 0; # make sure that $commit is valid

    my $result = get-output cwd => $repo,
                            |(|<git rev-list -1>, # use rev-list to handle tags
                              ($short ?? ‘--abbrev-commit’ !! Empty), $commit);

    return if     $result<exit-code> ≠ 0;
    return unless $result<output>;
    $result<output>
}

#↓ Pulls an archive with rakudo build from mothership (Whateverable
#↓ server). The file can be a .zst archive with just one build or an
#↓ .lrz archive with multiple builds. Keep in mind that these archives
#↓ must be used with --absolute-names argument to tar because older
#↓ rakudo versions will never become relocatable.
sub fetch-build($full-commit-hash, :$backend!) is export {
    my $done;
    if %*ENV<TESTABLE> { # keep asking for more time
        $done = Promise.new;
        start react {
            whenever $done { done }
            whenever Supply.interval: 0.5 { test-delay }
        }
    }
    LEAVE .keep with $done;

    my $ua = HTTP::UserAgent.new;
    $ua.timeout = 10;

    my $arch = $*KERNEL.name ~ ‘-’ ~ $*KERNEL.hardware;
    my $link = “{$CONFIG<mothership>}/$full-commit-hash?type=$backend&arch=$arch”;
    note “Attempting to fetch $full-commit-hash…”;

    my $response = $ua.get: :bin, $link;
    return unless $response.is-success;

    my $disposition = $response.header.field(‘Content-Disposition’).values[0];
    return unless $disposition ~~ /‘filename=’\s*(<.xdigit>+[‘.zst’|‘.lrz’])/;

    my $location = $CONFIG<archives-location>.IO.add: $backend;
    my $archive  = $location.add: ~$0;
    spurt $archive, $response.content, :bin;

    if $archive.ends-with: ‘.lrz’ { # populate symlinks
        my $proc = run :out, :bin, <lrzip -dqo - -->, $archive;
        my $list = run :in($proc.out), :out, <tar --list --absolute-names>;
        my @builds = gather for $list.out.lines { # TODO assumes paths without newlines, dumb but I don't see another way
            take ~$0 if /^‘/tmp/whateverable/’$backend‘/’(<.xdigit>+)‘/’/;
        }
        for @builds.unique {
            my $symlink = $location.add: $_;
            $symlink.unlink if $symlink.e; # remove existing (just in case)
            $archive.IO.symlink: $symlink;
        }
    }

    return $archive
}

#↓ Checks if rakudo build for $full-commit-hash exists. This sub will
#↓ automatically fetch an archive from mothership (Whateverable server)
#↓ if the build is not found locally (set $force-local to avoid that).
#↓ See &fetch-build for more info on pulling archives from the server.
sub build-exists($full-commit-hash,
                 :$backend=‘rakudo-moar’,
                 :$force-local=False) is export {
    my $archive     = “$CONFIG<archives-location>/$backend/$full-commit-hash.zst”.IO;
    my $archive-lts = “$CONFIG<archives-location>/$backend/$full-commit-hash”.IO;
    # ↑ long-term storage (symlink to a large archive)

    my $answer = ($archive, $archive-lts).any.e.so;
    if !$force-local && !$answer && $CONFIG<mothership> {
        return so fetch-build $full-commit-hash, :$backend
    }
    $answer
}

#↓ Lists some git tags.
sub get-tags($date, :$repo=$CONFIG<rakudo>, :$dups=False, :@default=(‘HEAD’,)) is export {
    my @tags = @default;
    my %seen;
    for get-output(cwd => $repo, <git tag -l>)<output>.lines.reverse -> $tag {
        next unless $tag ~~ /^(\d\d\d\d\.\d\d)[\.\d\d?]?$/;
        next if Date.new($date) after Date.new($0.trans(‘.’=>‘-’)~‘-20’);
        next if $dups.not && %seen{~$0}++;
        @tags.push(~$tag)
    }
    @tags.reverse
}

sub get-commits($_, :$repo=$CONFIG<rakudo>) is export {
    return .split: /‘,’\s*/ if .contains: ‘,’;

    if /^ $<start>=\S+ ‘..’ $<end>=\S+ $/ {
        if run(:out(Nil), :err(Nil), :cwd($repo),
               ‘git’, ‘rev-parse’, ‘--verify’, $<start>).exitcode ≠ 0 {
            grumble “Bad start, cannot find a commit for “$<start>””
        }
        if run(:out(Nil), :err(Nil), :cwd($repo),
               ‘git’, ‘rev-parse’, ‘--verify’, $<end>).exitcode   ≠ 0 {
            grumble “Bad end, cannot find a commit for “$<end>””
        }
        my $result = get-output :cwd($repo), ‘git’, ‘rev-list’, ‘--reverse’,
                                “$<start>^..$<end>”; # TODO unfiltered input
        grumble ‘Couldn't find anything in the range’ if $result<exit-code> ≠ 0;
        my @commits = $result<output>.lines;
        if @commits.elems > $CONFIG<commits-limit> {
            grumble “Too many commits ({@commits.elems}) in range,”
                  ~ “ you're only allowed $CONFIG<commits-limit>”
        }
        return @commits
    }
    return get-tags ‘2015-12-24’, :$repo if /:i ^ [ releases | v? 6 ‘.’? c ] $/;
    return get-tags ‘2014-01-01’, :$repo if /:i ^   all                      $/;
    return ~$<commit>                    if /:i ^   compare \s $<commit>=\S+ $/;
    return $_
}

#↓ Fuzzy search for SHAs and tags
sub get-similar($tag-or-hash, @other?, :$repo=$CONFIG<rakudo>) is export {
    my @options = @other;
    my @tags = get-output(cwd => $repo, <git tag>,
                          ‘--format=%(*objectname)/%(objectname)/%(refname:strip=2)’,
                          ‘--sort=-taggerdate’)<output>.lines
                          .map(*.split(‘/’))
                          .grep({ build-exists .[0] || .[1],
                                               :force-local })
                          .map(*[2]);

    my $cutoff = $tag-or-hash.chars max 7;
    my @commits = get-output(cwd => $repo, ‘git’, ‘rev-list’,
                             ‘--all’, ‘--since=2014-01-01’)<output>
                      .lines.map(*.substr: 0, $cutoff);

    # flat(@options, @tags, @commits).min: { sift4($_, $tag-or-hash, 5, 8) }
    my $ans = ‘HEAD’;
    my $ans_min = ∞;

    use Text::Diff::Sift4;
    for flat @options, @tags, @commits {
        my $dist = sift4 $_, $tag-or-hash, $cutoff;
        if $dist < $ans_min {
            $ans = $_;
            $ans_min = $dist;
        }
    }
    $ans
}

# vim: expandtab shiftwidth=4 ft=perl6

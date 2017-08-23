#!/usr/bin/env perl6
# Copyright © 2017
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
use Misc;

use IRC::Client;

unit class Releasable does Whateverable;

# ↓ Git itself suggests 9 characters, and 12 characters may be a better
# ↓ choice for the hundred-year language… but let's increase it only
# ↓ when needed
my $SHA-LENGTH   = 8;
my $RELEASE-HOUR = 19; # GMT+0
my $BLOCKERS-URL = ‘https://perl6.fail/release/blockers.json’;
my $TICKET-URL   = ‘https://rt.perl.org/rt3/Public/Bug/Display.html?id=’;

method help($msg) {
    “status | status link”
}

sub ignored-commits() {
    my $last-release = to-full-commit chomp slurp “$RAKUDO/VERSION”;
    die ‘Cannot resolve the tag for the last release’ unless $last-release;
    my $result = run :out, :cwd($RAKUDO), ‘git’, ‘log’, ‘--pretty=%b’,
                     ‘-z’, “$last-release..HEAD”, ‘--’, ‘docs/ChangeLog’;
    die ‘Cannot git log the changelog’ unless $result;

    return gather for $result.out.split(0.chr, :skip-empty) {
        next unless /‘not logged’\N*‘:’ \s* [ @<shas>=[<.xdigit>**4..* ] ]+ % \s+/;
        { take ~$_ if .chars == $SHA-LENGTH } for @<shas>
    }
}

sub time-left($then) {
    my $time-left = $then.Instant - now;
    return ‘will happen when it's ready’ if $time-left < 0;
    my ($seconds, $minutes, $hours, $days) = $time-left.polymod: 60, 60, 24;
    return ‘is just a few moments away’ if not $days and not $hours;
    my $answer = ‘in ’;
    $answer ~= “$days day{$days ≠ 1 ?? ‘s’ !! ‘’} and ” if $days;
    $answer ~= “≈$hours hour{$hours ≠ 1 ?? ‘s’ !! ‘’}”;
    $answer
}

sub time-to-release($msg) {
    my $guide = slurp “$RAKUDO/docs/release_guide.pod”;
    die ‘Unable to parse the release guide’ unless $guide ~~ /
    ^^ ‘=head2 Planned future releases’ $$
    .*?
    (^^‘  ’(\d\d\d\d‘-’\d\d‘-’\d\d)\s+ ‘Rakudo #’(\d+) [\s+‘(’ (<-[)]>+) ‘)’]? \n)+
    /;
    my @dates = $0.map: { %(date => Date.new(~.[0]), id => +.[1], manager => (.Str with .[2])) };
    my $important-date;
    my $annoying-warning = False;
    for @dates {
        my $release = .<date>.yyyy-mm-dd.split(‘-’)[0,1].join: ‘.’;
        if not to-full-commit $release {
            $important-date = $_;
            if not .<manager> and not $annoying-warning {
                $msg.reply: “Release manager is not specified yet.”
            }
            last
        }
        if not $annoying-warning {
            $annoying-warning = True;
            $msg.reply: “Release date for Rakudo $release is listed in”
                  ~ “ “Planned future releases”, but it was already released.”;
        }
    }
    die ‘Release date not found’ without $important-date;
    my $time-left = time-left DateTime.new(date => $important-date<date>,
                                           hour => $RELEASE-HOUR);
    “Next release $time-left”
}

sub changelog-to-stats($changelog) {
    if not $changelog.match: /^ ‘New in ’ (.*?) ‘:’ (.*?) ^^ ‘New in ’ (.*?) ‘:’/ {
        return { summary => ‘Unknown changelog format’ }
    }
    my ($version, $changes, $version-old) = ~$0, ~$1, ~$2;

    my $actual-commit = to-full-commit $version;
    my $actual-commit-old;
    my $summary;
    with $actual-commit {
        $summary = ‘Changelog for this release was not started yet’;
        $actual-commit-old = $actual-commit
    }
    $actual-commit-old //= to-full-commit $version-old;
    die ‘Cannot resolve the tag for the previous release’ without $actual-commit-old;

    my @shas = $changes.match(:g, / [‘[’ (<.xdigit>**4..*) ‘]’ \s*]+ $$/)»[0].flat».Str;
    my $result = run :out, :cwd($RAKUDO), ‘git’, ‘log’, ‘-z’, ‘--pretty=%H’,
                     ‘--reverse’, “$actual-commit-old..HEAD”;
    die ‘Failed to query rakudo git log’ unless $result;
    my @git-commits = $result.out.slurp-rest.split(0.chr, :skip-empty)
                                            .map: *.substr: 0, $SHA-LENGTH;
    my @warnings;
    my $commits-mentioned = ∅;
    if not defined $actual-commit { # if changelog was started
        $commits-mentioned = set gather for @shas {
            when .chars ≠ $SHA-LENGTH {
                @warnings.push: “$_ should be $SHA-LENGTH characters in length”
            }
            when @git-commits.none {
                @warnings.push: “$_ was referenced but there is no commit with this id”
            }
            default { take $_ }
        }
    }
    my $ignored = set ignored-commits;
    my @unlogged = @git-commits.grep: * !∈ ($commits-mentioned ∪ $ignored); # ordered
    $summary //= “{@git-commits - @unlogged} out of {+@git-commits} commits logged”;
    { :$summary, :@unlogged, :@warnings }
}

sub blockers() {
    use HTTP::UserAgent;
    my $ua = HTTP::UserAgent.new;
    my $response = try { $ua.get: $BLOCKERS-URL };
    return { summary => ‘R6 is down’ } without $response;
    return { summary => ‘R6 is down’ } unless $response.is-success;
    if $response.content-type ne ‘application/json;charset=UTF-8’ {
        return { summary => ‘R6 is weird’ }
    }
    my %data = from-json $response.decoded-content;
    return { summary => ‘R6 is weird’ } unless %data<tickets>:exists;
    my @tickets = %data<tickets>.list;
    return { summary => ‘No blockers’ } unless @tickets;
    my $summary = “{+@tickets} blocker{@tickets ≠ 1 ?? ‘s’ !! ‘’}”;
    {:$summary, :@tickets}
}

multi method irc-to-me($msg where /^ \s* [changelog|status|release|when]‘?’?
                                    [\s+ $<url>=[‘http’.*]]? $/) {
    my $changelog = process-url ~$_, $msg        with    $<url>;
    $changelog  //= slurp “$RAKUDO/docs/ChangeLog”;
    my $answer    = time-to-release($msg) ~ ‘. ’ without $<url>;
    my %stats     = changelog-to-stats $changelog;
    my %blockers  = blockers                     without $<url>;

    # ↓ All code here just to make the message pretty ↓
    $answer ~= “$_. ” with %blockers<summary>;
    $answer ~= %stats<summary>;
    $answer ~= “ (⚠ {+%stats<warnings>} warnings)” if %stats<warnings>;
    $msg.reply: $answer;
    return if none %blockers<tickets>, %stats<unlogged>, %stats<warnings>;

    # ↓ And here just to make a pretty gist ↓
    my &escape-html = { .trans: (‘&’, ‘<’, ‘>’) => (‘&amp;’, ‘&lt;’, ‘&gt;’) };
    my %files;

    my $blockers = join “\n”, (%blockers<tickets> // ()).map: { ‘<a href="’
                              ~ $TICKET-URL ~ .<ticket_id> ~ ‘">RT #’
                              ~ .<ticket_id> ~ ‘</a> ’ ~ escape-html .<subject> };
    %files<!blockers!.md> = ‘<pre>’ ~ $blockers ~ ‘</pre>’ if %blockers<tickets>;

    my $warnings = .join(“\n”) with %stats<warnings>;
    %files<!warnings!> = $warnings if $warnings;

    if %stats<unlogged> {
        my $descs = run :out, :cwd($RAKUDO), ‘git’, ‘show’,
                        ‘--format=%s’,
                        “--abbrev=$SHA-LENGTH”, ‘--quiet’, |%stats<unlogged>;
        my $links = run :out, :cwd($RAKUDO), ‘git’, ‘show’,
                        ‘--format=[<a href="’ ~ $RAKUDO-REPO ~ ‘/commit/%H">%h</a>]’,
                        “--abbrev=$SHA-LENGTH”, ‘--quiet’, |%stats<unlogged>;
        my $unreviewed = join “\n”, ($descs.out.lines Z $links.out.lines).map:
                         {‘    + ’ ~ escape-html(.[0]) ~ ‘ ’ ~ .[1]};
        %files<unreviewed.md> = ‘<pre>’ ~ $unreviewed ~ ‘</pre>’ if $unreviewed;
    }
    (‘’ but FileStore(%files)) but PrettyLink({“Details: $_”})
}

Releasable.new.selfrun: ‘releasable6’, [ / release6? <before ‘:’> /,
                                         fuzzy-nick(‘releasable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

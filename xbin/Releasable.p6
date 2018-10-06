#!/usr/bin/env perl6
# Copyright © 2017-2018
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
use Whateverable::Processing;

use IRC::Client;

unit class Releasable does Whateverable;

# ↓ Git itself suggests 9 characters, and 12 characters may be a better
# ↓ choice for the hundred-year language… but let's increase it only
# ↓ when needed
my $SHA-LENGTH       = 8;
my $RELEASE-HOUR     = 19; # GMT+0
my $BLOCKERS-URL-RT  = ‘https://fail.rakudo.party/release/blockers.json’;
my $BLOCKERS-URL-GH  = ‘https://api.github.com/repos/rakudo/rakudo/issues?state=open&labels=%E2%9A%A0%20blocker%20%E2%9A%A0’;
my $DRAFT-URL        = ‘https://raw.github.com/wiki/rakudo/rakudo/ChangeLog-Draft.md’;
my $DRAFT-USER-URL   = ‘https://github.com/rakudo/rakudo/wiki/ChangeLog-Draft’;

method help($msg) {
    “status | status link”
}

sub ignored-commits() {
    my $last-release = to-full-commit chomp slurp “$CONFIG<rakudo>/VERSION”;
    die ‘Cannot resolve the tag for the last release’ unless $last-release;
    my $result = run :out, :cwd($CONFIG<rakudo>), <git log --pretty=%b -z>,
                     “$last-release..%*BOT-ENV<branch>”, ‘--’, ‘docs/ChangeLog’;
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
    $answer ~= “≈$days day{$days ≠ 1 ?? ‘s’ !! ‘’} and ” if $days;
    $answer ~= “≈$hours hour{$hours ≠ 1 ?? ‘s’ !! ‘’}”;
    $answer
}

sub parse-next-release($msg) {
    my $guide = slurp “$CONFIG<rakudo>/docs/release_guide.pod”;
    die ‘Unable to parse the release guide’ unless $guide ~~ /
    ^^ ‘=head2 Planned future releases’ $$
    .*?
    (^^‘  ’(\d\d\d\d‘-’\d\d‘-’\d\d)\s+ ‘Rakudo #’(\d+) [\s+‘(’ (<-[)]>+) ‘)’]? \n)+
    /;
    my @dates = $0.map: { %(date => Date.new(~.[0]), id => +.[1], manager => (.Str with .[2])) };
    my $important-date;
    my $annoying-warning = False; # only one annoying message can printed (so far none)
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
    DateTime.new: date => $important-date<date>,
                  hour => $RELEASE-HOUR;
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
    my $result = run :out, :cwd($CONFIG<rakudo>), <git log -z --pretty=%H>,
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

sub blockers-rt() {
    use HTTP::UserAgent;
    my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
    my $response = try { $ua.get: $BLOCKERS-URL-RT };
    return ‘R6 is down’ without $response;
    return ‘R6 is down’ unless $response.is-success;
    if $response.content-type ne ‘application/json;charset=UTF-8’ {
        return ‘Cannot parse the data from R6’
    }
    my %data = from-json $response.decoded-content;
    return ‘Cannot parse the data from R6’ unless %data<tickets>:exists;
    %data<tickets>.List
}

sub blockers-github() {
    use HTTP::UserAgent;
    my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
    my $response = try { $ua.get: $BLOCKERS-URL-GH };
    return ‘GitHub is down’ without $response;
    return ‘GitHub is down’ unless $response.is-success;
    if $response.content-type ne ‘application/json; charset=utf-8’ {
        return ‘Cannot parse the data from GitHub’
    }
    from-json($response.decoded-content).List
}

sub blockers {
    my @tickets;
    my $summary = ‘’;
    for (blockers-rt(), blockers-github()) {
        when Str        { $summary ~= ‘, ’ if $summary; $summary ~= $_ }
        when Positional { @tickets.append: $_ }
        default         { die “Expected Str or Positional but got {.^name}” }
    }
    if @tickets == 0 {
        $summary ~= ‘. ’ if $summary;
        $summary ~= ‘There are no known blockers’;
    } else {
        $summary ~= ‘. At least ’ if $summary;
        $summary ~= “{+@tickets} blocker{@tickets ≠ 1 ?? ‘s’ !! ‘’}”;
    }
    # TODO share some logic with reportable

    my $list = join ‘’, @tickets.map: {
        my $url   = .<html_url> // .<url>;
        my $id    = .<number>   // .<ticket_id>;
        my $title = .<title>    // .<subject>;
        $id = (.<html_url> ?? ‘GH#’ !! ‘RT#’) ~ $id; # ha-ha 🙈
        $id .= fmt: ‘% 9s’;
        “<a href="$url">” ~ $id ~ “</a> {html-escape $title}\n”
    }
    %(:$summary, :$list)
}

multi method irc-to-me($msg where /^ :i \s*
                                    [changelog|release|log|status|info|when|next]‘?’?
                                    [\s+ $<url>=[‘http’.*]]? $/) {
    my $changelog = process-url ~$_, $msg with $<url>;
    $changelog  //= slurp “$CONFIG<rakudo>/docs/ChangeLog”;
    without $<url> {
        use HTTP::UserAgent;
        my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
        my $response = try { $ua.get: $DRAFT-URL };
        if $response and $response.is-success {
            my $wiki = $response.decoded-content;
            temp $/;
            $wiki .= subst: /^ .*? ^^<before New>/, ‘’;
            $changelog = $wiki ~ “\n” ~ $changelog;
        }
    }
    my %stats     = changelog-to-stats $changelog;

    my $answer;
    my %blockers;
    without $<url> {
        my $datetime  = parse-next-release $msg;
        my $time-left = time-left $datetime;
        $answer       = “Next release $time-left. ”;
        %blockers     = blockers;
    }

    # ↓ All code here just to make the message pretty ↓
    $answer ~= “$_. ” with %blockers<summary>;
    $answer ~= %stats<summary>;
    $answer ~= “ (⚠ {+%stats<warnings>} warnings)” if %stats<warnings>;
    $msg.reply: $answer;
    return if none %blockers<list>, %stats<unlogged>, %stats<warnings>;

    # ↓ And here just to make a pretty gist ↓
    my %files;
    %files<!blockers!.md> = ‘<pre>’ ~ %blockers<list> ~ ‘</pre>’ if %blockers<list>;

    my $warnings = .join(“\n”) with %stats<warnings>;
    %files<!warnings!> = $warnings if $warnings;

    if %stats<unlogged> {
        my $descs = run :out, :cwd($CONFIG<rakudo>), ‘git’, ‘show’,
                        ‘--format=%s’,
                        “--abbrev=$SHA-LENGTH”, ‘--quiet’, |%stats<unlogged>;
        my $links = run :out, :cwd($CONFIG<rakudo>), ‘git’, ‘show’,
                        ‘--format=[<a href="’ ~ $CONFIG<rakudo-repo> ~ ‘/commit/%H">%h</a>]’,
                        “--abbrev=$SHA-LENGTH”, ‘--quiet’, |%stats<unlogged>;
        my $unreviewed = join “\n”, ($descs.out.lines Z $links.out.lines).map:
                         {‘    + ’ ~ html-escape(.[0]) ~ ‘ ’ ~ .[1]};
        %files<unreviewed.md> = ‘<pre>’ ~ $unreviewed ~ ‘</pre>’ if $unreviewed;
    }
    (‘’ but FileStore(%files)) but PrettyLink({“Details: $_”})
}

sub remind($msg, @channels) {
    my $datetime = parse-next-release $msg;
    return without $datetime;
    my $time-left = time-left $datetime;
    my $text = “Next release $time-left”;
    $text ~= ‘. ’ ~ blockers<summary>;
    $text ~= ‘. Please log your changes in the ChangeLog: ’;
    $text ~= $DRAFT-USER-URL;
    for @channels {
        $msg.irc.send-cmd: ‘PRIVMSG’, $_, $text, :server($msg.server)
    }
}

multi method keep-reminding($msg) {
    # TODO multi-server setup not supported (this will be irrelevant after #284)
    loop {
        my &bail = { sleep $CONFIG<releasable><spam-exception-delay>; next }
        my $datetime = parse-next-release $msg;
        bail without $datetime;
        my $diff = $datetime - DateTime.now;
        bail if $diff < 0; # past the deadline
        bail if $diff > $CONFIG<releasable><spam-before>; # not close enough
        my $every = $CONFIG<releasable><spam-every>;
        bail if $diff < $every; # too close to the release
        my $left = $diff % $every;
        sleep $left;
        remind $msg, $CONFIG<releasable><spammed-channels>
    }
    CATCH { default { self.handle-exception: $_, $msg } }
}

multi method irc-connected($msg) {
    once start self.keep-reminding: $msg
}


my %*BOT-ENV = branch => ‘master’;

Releasable.new.selfrun: ‘releasable6’, [ / release6? <before ‘:’> /,
                                         fuzzy-nick(‘releasable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

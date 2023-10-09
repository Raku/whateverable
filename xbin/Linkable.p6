#!/usr/bin/env perl6
# Copyright © 2019-2023
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
# Copyright © 2017-2018
#     Zoffix Znet
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

unit class Linkable does Whateverable;

method help($msg) {
    ‘Like this: R#1946 D#1234 MOAR#768 NQP#509 SPEC#242 RT#126800 S09:320 524f98cdc’
}
method private-messages-allowed() { True }

constant %TICKET-URLS = %(
    ‘R’ | ‘RAKUDO’ | ‘GH’   => ‘https://api.github.com/repos/rakudo/rakudo/issues/’,
    ‘M’ | ‘MOAR’ | ‘MOARVM’ => ‘https://api.github.com/repos/MoarVM/MoarVM/issues/’,
    ‘N’ | ‘NQP’             => ‘https://api.github.com/repos/Raku/nqp/issues/’,
    ‘S’ | ‘SPEC’ | ‘ROAST’  => ‘https://api.github.com/repos/Raku/roast/issues/’,
    ‘D’ | ‘DOC’ | ‘DOCS’    => ‘https://api.github.com/repos/Raku/doc/issues/’,
    ‘PS’                    => ‘https://api.github.com/repos/Raku/problem-solving/issues/’,
);

sub bold($_) { $_ }
# XXX ↓ currently it's too smart and it will escape it… hmm…
# sub bold($_) { use IRC::TextColor; ircstyle :bold, $_ }

my $RECENT-EXPIRY = %*ENV<DEBUGGABLE> || %*ENV<TESTABLE> ?? 5 !! 2 × 60;
my %recently;
sub recent($what) {
    # throw away old entries
    %recently .= grep: now - *.value ≤ $RECENT-EXPIRY;

    LEAVE %recently{$what} = now; # mark it
    %recently{$what}:exists
}

my Channel $channel-messages .= new;

sub link-reply($msg, $answer) {
    return if recent “{$msg.?channel // $msg.nick}\0$answer”;
    sleep 3 if $msg.nick eq ‘Geth’;
    $channel-messages.send: %(:$msg, :$answer)
}

start react whenever $channel-messages.Supply.throttle: 3, 3 -> $ (:$msg, :$answer) {
    $msg.irc.send: :where($msg.?channel // $msg.nick), text => $answer;
}

sub link-doc-page($msg, $match) {
    my $path = ~$match<path>;
    $path .= subst: /^ ‘doc/’ /, ‘’;
    $path .= subst: / [‘.rakudoc’ | ‘.pod6’] $/, ‘’;
    if $path.contains: ‘Type’ {
        $path .= subst: ‘Type’, ‘type’;
        $path .= subst: ‘/’, ‘::’, :th(2..*);
    } else {
        $path .= subst: ‘Language’, ‘language’
    }
    link-reply $msg, “Link: https://docs.raku.org/$path”
}

sub link-old-design-docs($msg, $match) {
    $/ = $match;
    my $syn    = $<subsyn> ?? “$<syn>/$<subsyn>” !! $<syn>;
    my $anchor = $<line>   ?? “line_” ~ $<line>  !! $<entry>;
    link-reply $msg, “Link: https://design.Raku.org/$syn.html#$anchor”
}

sub link-github-ticket($msg, $match) {
    my $prefix = ($match<prefix-explicit> // $match<prefix>).uc;
    my $id     = $match<id>;
    with fetch $prefix, $id {
        link-reply $msg, “{bold “$prefix#{.<id>} [{.<status>}]”}: {.<url>} {bold .<title>}”
    }
}

sub link-rt-ticket($msg, $match) {
    # XXX temporary solution? or maybe not?
    my $id = +$match<id>;
    my $ticket-snapshot = ‘data/reportable/’.IO.dir.sort.tail.add(‘RT’).add($id);
    next unless $ticket-snapshot.e;
    my $data = from-json $ticket-snapshot.slurp;
    my $url = “https://rt.perl.org/Ticket/Display.html?id=$id”;
    $url ~= “ https://rt-archive.perl.org/perl6/Ticket/Display.html?id=$id”;
    with $data {
        link-reply $msg, “{bold “RT#$id [{.<Status>}]”}: {bold .<Subject>} $url”
    }
}

sub link-commit($msg, $match) {
    my $sha = $match<id>;
    my $data = try curl “https://api.github.com/search/commits?q=$sha”,
                        headers => (Accept => ‘application/vnd.github.cloak-preview’,);
    return without $data;
    my %json := $data;
    if %json<items> == 1 {
        my $commit = %json<items>[0];
        my $short-sha = $commit<sha>.substr: 0, 10; # XXX use get-short-commit ?
        my $url = $commit<html_url>.subst: $commit<sha>, $short-sha;
        my $title = $commit<commit><message>.lines[0];
        my $date = DateTime.new($commit<commit><author><date>).Date;
        link-reply $msg, “($date) $url $title”
    }
}

sub match-and-dispatch($msg) {
    my $by-bot = $msg.nick.starts-with: ‘Geth’;
    # Doc pages
    if $by-bot and
    $msg.text.match: /^ ‘¦ doc: ’ .* ‘|’ \s+ $<path>=[‘doc/’ < Type Language > .*] $/ {
        link-doc-page $msg, $/;
    }
    # Old design docs
    for $msg.text.match: :g, / « $<syn>=[S\d\d]
            [ ‘/’ $<subsyn>=[\w+] ]? ‘:’ [ $<line>=[\d+] | $<entry>=[\S+]]
            <?{ $<entry> or $<line> ≤ 99999 }>
            / {
        # unlike the old bot this won't support space-separated
        # anchors because of situations like this:
        # https://colabti.org/irclogger/irclogger_log/perl6-dev?date=2016-09-22#l87
        link-old-design-docs $msg, $_;
    }
    # GitHub tickets
    for $msg.text.match: :g, /:i « $<prefix>=[@(%TICKET-URLS.keys)]
                                 ‘#’ \s* $<id>=[\d**1..6] / {
        link-github-ticket $msg, $_;
    }
    if $by-bot {
        for $msg.text.match: :ex, /^ ‘¦ ’ $<prefix>=[\S+] ‘: ’ .*?
                                 <!after ‘created pull request ’> # exclude new PR notifications
                                 <!after   ‘Merge pull request ’> # exclude mentions of PR merges
                                 <!after \w>                      # everything was handled earlier
                                 ‘#’     $<id>=[\d**1..6] » / {
            link-github-ticket $msg, $_
        }
    }
    # RT Tickets
    for $msg.text.match: :g, / « RT \s* ‘#’? \s* $<id>=[\d**{5..6}] » / {
        link-rt-ticket $msg, $_;
    }
    # Commits
    if not $by-bot {
        for $msg.text.match: :g, / <!after ‘:’> [^|\s+] « $<id>=[<xdigit>**{8..40}] » [\s+|$] / {
            next if .<id>.comb.unique < 4; # doesn't look like a random commit!
            link-commit $msg, $_;
        }
    }
    Nil # This is important!
}

multi method irc-privmsg-channel($msg where /^ ‘.bots’ \s* $/) {
    ‘Docs for all whateverable bots: https://github.com/Raku/whateverable/wiki’
}

# TODO Currently there's a chance that it will not respond to some
#      direct messages at all, it should *always* say something.
multi method irc-privmsg-channel($msg) { match-and-dispatch $msg }
multi method irc-to-me($msg)           { match-and-dispatch $msg }

sub fetch($prefix, $id) {
    my $url = %TICKET-URLS{$prefix} ~ $id;
    my %json := curl $url;
    my $tags = %json<labels>.map({‘[’ ~ .<name> ~ ‘]’}).join;

    %(
        url    => %json<html_url>,
        title  => join(‘ ’, ($tags || Empty), %json<title>),
        id     => ~%json<number>,
        status =>  %json<state>,
    )
}


Linkable.new.selfrun: ‘linkable6’, [ fuzzy-nick(‘linkable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

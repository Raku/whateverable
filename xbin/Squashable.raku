#!/usr/bin/env raku
# Copyright © 2017-2023
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

use IRC::Client;

unit class Squashable does Whateverable;

my $WIKI-PAGE-URL = ‘https://github.com/rakudo/rakudo/wiki/Monthly-Bug-Squash-Day’;
my $WIKI-PAGE-URL-RAW = ‘https://raw.githubusercontent.com/wiki/rakudo/rakudo/Monthly-Bug-Squash-Day.md’;
my $TIMEZONE-RANGE = (-12..20) × 60×60; # in seconds (let's be inclusive?)
my $CHANNEL = %*ENV<DEBUGGABLE> ?? ‘#whateverable’ !! ‘#raku’;
my $PATH = ‘data/squashable’.IO;

my $next-event-lock = Lock.new;
my $next-event;
my $quiet-mode = False; # TODO is it safe or not?

method help($msg) {
    “Available commands: status, log, quiet, loud”
}

sub squashathon-range(Date $date) {
    (DateTime.new(:$date, timezone => $TIMEZONE-RANGE.max,
                  :00hour, :00minute, :00second).Instant)
    ..
    (DateTime.new(:$date, timezone => $TIMEZONE-RANGE.min,
                  :23hour, :59minute, :59second).Instant)
}

sub set-next-squashathon() {
    use HTTP::UserAgent;
    my $ua = HTTP::UserAgent.new;
    my $response = try { $ua.get: $WIKI-PAGE-URL-RAW };
    grumble ‘GitHub is down’ without $response;
    grumble ‘GitHub is down’ unless $response.is-success;
    if $response.content-type ne ‘text/plain; charset=utf-8’ {
        grumble ‘GitHub is weird’
    }
    my $page = $response.decoded-content;
    grumble ‘Can't parse the wiki page’ unless
    $page ~~ / ^^ ‘## Dates’                              \N*\n
               ^^ ‘|’ \s* ‘Date’ \s* ‘|’                  \N*\n
              [^^ ‘|’[‘-’|‘:’]                            \N*\n]?
              [^^ ‘|’ \s* [‘🍕’|‘<br>’|‘[’|‘*’|‘~’]*
                   \s* $<dates>=[\d\d\d\d\-\d\d\-\d\d] >> \N*\n]+ /;
    my @dates = $<dates>.list.map: { Date.new: ~$_ };
    grumble ‘Can't parse the wiki page’ unless @dates;
    for @dates {
        if now < squashathon-range($_).max {
            $next-event-lock.protect: { $next-event = $_ }
            return
        }
    }
    grumble ‘The date for the next SQUASHathon is not set’
}

multi method irc-to-me($msg where /:i [ ‘quiet’ | ‘off’ | ‘shut up’ ] /) {
    $quiet-mode = True;
    ‘.oO( Mmmm… pizza! )’
}

multi method irc-to-me($msg where /:i [ ‘loud’ | ‘on’ ] /) {
    $quiet-mode = False;
    ‘ALRIGHT, LET'S DO IT!!!’
}

multi method irc-to-me($msg where /^ \s* [log|status|info|when|next]
                                     [ \s+ $<date>=[\d\d\d\d\-\d\d\-\d\d]]?
                                                                     \s* $/) {
    my $next;
    my $date = $<date>;
    with $date {
        try $next = Date.new: ~$_;
        CATCH { grumble ‘Invalid date format’ }
        grumble “I don't know about SQUASHathon on $_” if not $PATH.add(~$_).d;
    } else {
        set-next-squashathon;
        $next = $next-event-lock.protect: { $next-event }
    }
    sub utc-hour($secs) { ($secs ≥ 0 ?? ‘+’ !! ‘-’) ~ abs $secs ÷ 60 ÷ 60 }
    my $when = “($next UTC{utc-hour $TIMEZONE-RANGE.min}⌁”
                    ~ “UTC{utc-hour $TIMEZONE-RANGE.max})”;
    my $next-range = squashathon-range $next;
    if $msg !~~ /‘log’/ and not $date {
        if now < $next-range.min {
            my $warn = ($next-range.min - now)÷60÷60÷24 < 7 ?? ‘⚠🍕 ’ !! ‘’;
            reply $msg, “{$warn}Next SQUASHathon {time-left $next-range.min} $when”
                            ~ “. See $WIKI-PAGE-URL”
        } else {
            reply $msg, “🍕🍕 SQUASHathon is in progress!”
                         ~ “ The end of the event {time-left $next-range.max}”
                         ~ “. See $WIKI-PAGE-URL”
        }
    }
    my %files;
    %files<~log> = slurp $PATH.add(“$next/log”) if $PATH.add(“$next/log”).e;
    if $PATH.add(“$next/state”).e {
        my %state = from-json slurp $PATH.add(“$next/state”);
        for %state<stats>.pairs {
            if .value ~~ Associative {
                %files<stats> ~= “\n{.key}:\n”;
                my $prev;
                for .value.pairs.sort(*.key) {
                    %files<stats> ~= “├ $prev\n” with $prev;
                    LAST %files<stats> ~= “└ $prev\n”;
                    $prev = “{.key}: {.value}”
                }
            } else {
                %files<stats> ~= “\n{.key}: {.value}\n”;
            }
        }
        %files<stats> //= ‘No stats yet. Be the first to contribute!’;
        %files<stats>  .= trim-leading;
    }
    return ‘Nothing there yet’ if $msg ~~ /‘log’/ and not %files;
    return unless %files;
    (‘’ but FileStore(%files)) but PrettyLink({“Log and stats: $_”})
}

use HTTP::Server::Async;
use JSON::Fast;

ensure-config;
my $server = HTTP::Server::Async.new: |($CONFIG<squashable><host port>:p).Capture;
my $channel = Channel.new;
my $squashable = Squashable.new;

# TODO failures here will blow up (or get ignored) without proper handling
$server.handler: sub ($request, $response) {
    my $next = $next-event-lock.protect: { $next-event }
    without $next {
        $response.status = 500; $response.close;
        return
    }
    use Digest::SHA1;
    use Digest::HMAC;
    my $body = $request.data;
    $body .= subbuf: 0..^($body - 1) if $body[*-1] == 0; # TODO trailing null byte. Why is it there?
    my $hmac = ‘sha1=’ ~ hmac-hex $CONFIG<squashable><secret>, $body, &sha1;
    if $hmac ne $request.headers<X-Hub-Signature> {
        $response.status = 400; $response.close(‘Signatures didn't match’);
        return
    }
    my $data = try from-json $body.decode;
    without $data {
        $response.status = 400; $response.close(‘Invalid JSON’);
        return
    }
    if $data<zen>:exists {
        my $text = “Webhook for {$data<repository><full_name>} is now ”
                 ~ ($data<hook><active>??‘active’!!‘inactive’) ~ ‘! ’
                 ~ $data<zen>;
        $squashable.irc.send: :$text, where => $CHANNEL; # TODO race?
    }
    if now !~~ squashathon-range $next {
        $response.status = 200; $response.close;
        return
    }
    my $file = $request.headers<X-GitHub-Delivery>;
    mkdir $PATH.add(“$next”);
    spurt $PATH.add(“$next/$file”), $body if $file ~~ /^ [<.xdigit>|‘-’]+ $/;

    $channel.send: $request.headers<X-GitHub-Event> => $data;
    $response.headers<Content-Type> = 'text/plain';
    $response.status = 200;
    $response.close
}

my %state;
try set-next-squashathon;
if $next-event.defined and $PATH.add(“$next-event/state”).e {
    %state = from-json slurp $PATH.add(“$next-event/state”)
} else {
    %state = contributors => SetHash.new, log => [], stats => %()
}

sub notify($text is copy, :$pizza = 1, :$silent = False, :$force = False) {
    $text = “{‘🍕’ x $pizza} $text”;
    my $next = $next-event-lock.protect: { $next-event }
    mkdir $PATH.add(“$next”);
    spurt $PATH.add(“$next/log”), “{DateTime.now: :0timezone} $text\n”, :append;
    if !$quiet-mode or $force { # $force makes it talk in quiet mode
        $squashable.irc.send: :$text, where => $CHANNEL if !$silent
    }
}

sub process-event($hook is copy, $data) { # TODO refactor
    $hook = ‘wiki’ if $hook eq ‘gollum’;
    my $login = $data<sender><login>;
    given $hook {
        when ‘wiki’ { # TODO doesn't say anything when you delete something
            for @($data<pages>) {
                my $title  = shorten .<title>, 50;
                my $action = .<action>;
                my $url    = .<html_url>;
                notify “$login++ $action wiki page “$title”: $url”;
                sleep 0.05
            }
        }
        when ‘issue_comment’ | ‘commit_comment’ | ‘pull_request_review_comment’ {
            my $action = $data<action>; # ‘created’, ‘edited’, or ‘deleted’
            $action = ‘wrote’ if $action eq ‘created’;
            my $title = do given $_ {
                when ‘issue_comment’  {
                    ““{shorten $data<issue><title>, 50}””
                }
                when ‘commit_comment’ { # TODO doesn't say anything when you delete something
                    “commit {$data<comment><commit_id>.substr: 0, 12}” # TODO get commit title?
                }
                when /^pull_request/  {
                    “a review for “{shorten $data<pull_request><title>, 50}””
                }
            }
            my $url = $data<comment><html_url>;
            notify “$login++ $action a comment on $title: $url”, :silent($action eq ‘edited’)
        }
        when ‘issues’ {
            my $action = $data<action>;
            my $title  = ‘“’ ~ shorten($data<issue><title>, 50) ~ ‘”’;
            my $url    = $data<issue><html_url>;
            if $action eq ‘assigned’ | ‘unassigned’ {
                my $assignee = $data<assignee><login>;
                if $assignee eq $login {
                    notify :silent, “$login++ self-$action issue $title: $url”
                } else {
                    my $where = $action eq ‘assigned’ ?? ‘to’ !! ‘from’;
                    notify :silent, “$login++ $action issue $title $where $assignee: $url”
                }
            } elsif $action eq ‘labeled’ | ‘unlabeled’ {
                my $label = $data<label><name>;
                notify “$login++ $action issue $title ($label): $url”
            } else {
                notify “$login++ $action issue $title: $url”
            }
        }
        when ‘pull_request_review’ {
            my $action = $data<action>;
            my $title  = ‘“’ ~ shorten($data<pull_request><title>, 50) ~ ‘”’;
            my $url    = $data<review><html_url>;
            notify “$login++ $action a review on pull request $title: $url”
        }
        when ‘pull_request’ {
            my $action = $data<action>;
            my $title  = ‘“’ ~ shorten($data<pull_request><title>, 50) ~ ‘”’;
            my $url    = $data<pull_request><html_url>;
            if $action eq ‘assigned’ | ‘unassigned’ {
                my $assignee = $data<assignee><login>;
                if $assignee eq $login {
                    notify “$login++ self-$action pull request $title: $url”
                } else {
                    my $where = $action eq ‘assigned’ ?? ‘to’ !! ‘from’;
                    notify “$login++ $action pull request $title $where $assignee: $url”
                }
            } elsif $action eq ‘review_requested’ {
                notify “$login++ requested a review on pull request $title: $url”
            } elsif $action eq ‘review_request_removed’ {
                # TODO not needed, right?
            } else {
                $action = ‘merged’ if $action eq ‘closed’ and $data<pull_request><merged>;
                notify “$login++ $action pull request $title: $url”
            }
        }
        when ‘push’ {
            my $commits = +$data<commits>; # ← TODO should be <size>
            %state<stats><commits> += $commits;
            notify :silent, “$login++ pushed $commits commit{$commits ≠ 1 ?? ‘s’ !! ‘’}”;
        }
        default { return }
    }
    if $login ∉ %state<contributors> {
        %state<contributors>{$login} = True;
        sleep 0.3;
        notify :3pizza, :force, “ First contribution by $login++! ♥”;
    }
    if $data<action>:exists {
        %state<stats>{$hook}{$data<action>}++
    } else {
        %state<stats>{$hook}++
    }
}

my $react = start react {
    whenever $server.listen {
        # TODO “done” or something?
    }
    whenever $channel {
        my $hook = .key;
        my $data  = .value;
        try {
            process-event $hook, $data;
            CATCH { default { .say } }
        }
        my $next = $next-event-lock.protect: { $next-event }
        mkdir $PATH.add(“$next”);
        spurt $PATH.add(“$next/state”), to-json %state;
    }
}


$squashable.selfrun: ‘squashable6’, [ / squash6? <before ‘:’> /,
                                      fuzzy-nick(‘squashable6’, 3) ]

# vim: expandtab shiftwidth=4 ft=perl6

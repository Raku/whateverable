#!/usr/bin/env perl6

use HTTP::UserAgent;
use JSON::Fast;

constant $URL = ‘https://irclog.perlgeek.de’;
constant @CHANNELS = <#perl6-dev #perl6 #p6dev #moarvm>;
constant $PATH = ‘data/irc’.IO;

my $ua = HTTP::UserAgent.new;
$ua.timeout = 10;

mkdir $PATH.add: $_ for @CHANNELS;

sub get($channel, $date) {
    my $file = $PATH.add($channel).add($date);
    return True if $file.e;
    loop {
        my $url = “$URL/{$channel.substr: 1}/$date”;
        my $response = $ua.get: $url, :bin, :Accept<application/json>;
        my $data = $response.content.decode;
        if not $response.is-success {
            if $data eq ‘{"error":"No such channel or day"}’ {
                note ‘That's it’;
                return False
            }
            note ‘Failed to get the page, retrying…’;
            sleep 0.5;
            redo
        }
        spurt $file, $data;
        return True;
    }
}

my $today = now.Date.pred; # always doesn't fetch the current day

note ‘Fetching…’;
for @CHANNELS -> $channel {
    note $channel;
    my $current-date = $today;
    loop {
        note $current-date;
        last unless get $channel, $current-date;
        $current-date .= pred;
    }
}

my num $jsontime = 0e0;
my num $totaltime = 0e0;

my num $starttime = now.Num;

my @json_errors;

note ‘Caching…’;
for @CHANNELS {
    my @msgs;
    my $total;
    my $channel-dir = $PATH.add: $_;
    for $channel-dir.dir.sort.reverse {
        .note;
        my $date = .basename;
        try {
            my str $source = slurp $_;
            my num $start = now.Num;
            my $jsondata = from-json($source)<rows>;
            $jsontime += now.Num - $start;

            for $jsondata.list {
                next without .[1];
                @msgs.push: (
                    .[3], # what
                    .[0], # id
                    # .[1], # who
                    # .[2], # when (posix)
                    $date,
                ).join: “\0”;
                $total++
            }
            CATCH { default { note “Skipping $date because of JSON issues $_”; @json_errors.push: $date.Str => $_.message } }
        }
    }
    note “Loaded $total messages”;
    spurt $channel-dir ~ ‘.total’, $total;
    spurt $channel-dir ~ ‘.cache’, @msgs.join: “\0\0”
}
$totaltime = now.Num - $starttime;

try spurt "fetch-irc-json-errors.err", @json_errors.fmt: "%s: %s", "\n";

note "total time spent caching: $totaltime";
note "total time spent json decoding: $jsontime";
note "ratio: { $jsontime / $totaltime }";

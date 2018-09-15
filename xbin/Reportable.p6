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
use Whateverable::Config;

use IRC::Client;

unit class Reportable does Whateverable;

my $dir = ‘data/reportable’.IO;
mkdir $dir;

ensure-config;

my $semaphore = Semaphore.new: 1;

my $next-date = now.DateTime.truncated-to: ‘day’;

if !%*ENV<DEBUGGABLE> and !%*ENV<TESTABLE> {
    start loop {
        $next-date .= later: :6hours;
        next if $next-date < now.DateTime;
        await Promise.at: $next-date.Instant;
        $semaphore.acquire; # released in the snapshot sub
        await snapshot
    }
}

sub report-dirs() {
    $dir.dir.sort # TODO be a little bit more selective, just in case
}

method help($msg) {
    ‘list | <from> <to> | weekly’
}

multi method irc-to-me($msg where ‘list’) {
    my $list = report-dirs.reverse.map(*.basename).join: “\n”;
    return ‘No snapshots yet!’ unless $list;
    ‘’ but ProperStr($list)
}

multi method irc-to-me($msg where ‘monthly’) {
    ‘You can implement this feature if you need it :)’
    ~ ‘ (meanwhile try to be more specific by using ｢list｣ command)’
}

multi method irc-to-me($msg where ‘weekly’) {
    ‘You can implement this feature if you need it :)’
    ~ ‘ (meanwhile try to be more specific by using ｢list｣ command)’
}

multi method irc-to-me($msg where ‘snapshot’) {
    if not $semaphore.try_acquire { # released in snapshot sub
        return ‘Already working on it! Check ｢list｣ command after a while.’
    }
    snapshot $msg;
}

multi method irc-to-me($msg where .Str.words == 2) {
    my ($from, $to) = $msg.Str.words;
    my $from-dir = report-dirs.first: *.basename.starts-with: $from;
    my $to-dir   = report-dirs.first: *.basename.starts-with: $to;
    my $hint = ‘(try ｢list｣ command to see what's available)’;
    grumble “Couldn't find a snapshot for $from $hint.” without $from-dir;
    grumble “Couldn't find a snapshot for $to $hint.”   without $to-dir;
    if $from-dir.basename gt $to-dir.basename {
        $msg.reply: ‘Anti-reports are not useful, so I switched the arguments for you.’;
        ($from-dir, $to-dir) = $to-dir, $from-dir
    }
    if $from-dir.basename eq $to-dir.basename {
        grumble “Can only generate a report from two different snapshots (both are {$from-dir.basename})”
    }
    $msg.reply: ‘OK, working on it! This may take up to 40 seconds’;
    my $report = join “\n”, gather analyze $from-dir, $to-dir;
    ‘’ but FileStore({ ‘report.md’ => $report })
}

sub snapshot($msg?) {
    start {
        use File::Temp;
        use File::Directory::Tree;
        LEAVE $semaphore.release; # TODO so what if the thread exits abruptly?
        my ($temp-folder,) = tempdir, :!unlink;
        CATCH {
            # TODO the message is not send when the snapshot is scheduled
            note ‘Failed to make the snapshot’;
            .irc.send-cmd: ‘PRIVMSG’, $CONFIG<cave>, “Failed to make the snapshot. Help me.”,
                           :server(.server), :prefix($CONFIG<caregivers>.join(‘, ’) ~ ‘: ’) with $msg;
            rmtree $_ with $temp-folder;
        }

        my $datetime = now.DateTime.truncated-to: ‘minute’;
        .reply: ‘OK! Working on it. This will take forever, so don't hold your breath.’ with $msg;

        my $env = %*ENV.clone;
        $env<PATH> = ‘/home/bisectable/.rakudobrew/bin/’ ~ ‘:’ ~ $env<PATH>; # TODO any better solution?
        mkdir “$temp-folder/GH”;
        run :$env, ‘maintenance/pull-gh’, “$temp-folder/GH”; # TODO authenticate on github to get rid of unlikely rate limiting
        mkdir “$temp-folder/RT”;
        run :$env, ‘maintenance/pull-rt’, “$temp-folder/RT”, |$CONFIG<reportable><RT><user pass>;

        # .move does not work with directories and .rename does not
        # work across devices, so just run ‘mv’
        run ‘mv’, ‘--’, $temp-folder, $dir.add: $datetime;
        True
    }
}

sub analyze(IO() $before-dir where .d, IO() $after-dir where .d) {
    use JSON::Fast;
    use fatal;

    my $RT-URL = ‘https://rt.perl.org/Ticket/Display.html?id=’;

    # ↓ These contain frankentickets (GH and RT formats
    #   glued together + some generated data)
    my %before;
    my %after;

    sub autopad(@arr) {
        my $max = @arr.map(*.match(/(‘[’ <-[\]]>+ ‘]’)/)[0].chars).max;
        @arr.map: *.subst: /(‘[’ <-[\]]>+ ‘]’)/, { ‘ ’ x ($max - $0.chars) ~ $0 }
    }

    sub is-half-resolved($before, $after) {
        my $testneeded-before = $before<tags>.any eq ‘testneeded’;
        my $testneeded-after  =  $after<tags>.any eq ‘testneeded’;
        !$testneeded-before and $testneeded-after;
    }

    sub process-rt(IO $file) {
        my %data = from-json $file.slurp;
        %data<tracker>    = ‘RT’;
        %data<number>     = +%data<id>.match: /\d+$/;
        %data<uni-id>     = ‘RT#’ ~ %data<number>;
        %data<html_url>   = $RT-URL ~ %data<number>;
        %data<updated_at> = %data<LastUpdated>;
        %data<state>      = %data<Status>;
        %data<is-open>    = %data<state> eq <new open stalled>.any;
        die ‘Oops’ unless %data<Subject> ~~ /^ [‘[’(\w+)‘]’]* %% \s* (.*) $/;
        %data<tags> = ( |$0».Str, |%data<CF.{Tag}>.comb(/\w+/) )».lc.unique; # CF.{Tag} is comma-separated
        %data<title> = ~$1;
        %data
    }

    sub process-gh(IO $file) {
        my %data = from-json $file.slurp;
        %data<uni-id>  = ‘GH#’ ~ %data<number>;
        %data<tracker> = ‘GH’;
        %data<is-open> = %data<state> eq ‘open’;
        %data<tags>    = %data<labels>»<name>».lc;
        %data
    }

    # TODO race-ize it once it stops SEGV-ing
    sub add(%where, %data) { %where{%data<uni-id>} = %data }
    my $before = now;
    note “RT before…”; add %before, process-rt $_ for $before-dir.add(‘RT’).dir;
    if $before-dir.add(‘GH’).d {
        note “GH before…”; add %before, process-gh $_ for $before-dir.add(‘GH’).dir;
    }
    note “RT after…”;  add  %after, process-rt $_ for  $after-dir.add(‘RT’).dir;
    if $after-dir.add(‘GH’).d {
        note “GH after…”;  add  %after, process-gh $_ for  $after-dir.add(‘GH’).dir;
    }
    say now - $before;

    my @resolved;
    my @half-resolved;
    my @updated;
    my @new;

    sub compare($a, $b) {
        # RT should come first. Just because ¯\_(ツ)_/¯
        return $b<tracker> cmp $a<tracker> if $a<tracker> ne $b<tracker>;
        $a<number> cmp $b<number>
    }
    for %after.values.sort(&compare) {
        my $before = %before{.<uni-id>} // %(state => ‘∅’, tags => ());
        my $after  = $_;

        my $subject = $after<title>;
        $subject .= subst(/^ \s* [‘[’ \w+ ‘]’]* %% \s* /, ‘’);
        $subject  = html-escape $subject; # TODO trim long subjects?
        my $link  = “<a href="{.<html_url>}">{sprintf ‘% 9s’, .<uni-id>}</a>”;
        my $str   = “$link $subject”;
        if $before<state> ne $after<state> {
            if $after<state> eq ‘resolved’|‘closed’ {
                @resolved.push: “[{$after<state>}] $str”;
                @new.push:      “[{$after<state>}] $str” if $before<state> eq ‘∅’;
            } else {
                if $before<state> eq ‘∅’ {
                    if is-half-resolved($before, $after) {
                        # created *and* half-resolved
                        @half-resolved.push: “[testneeded] $str”;
                        @new.push:           “[testneeded] $str”;
                    } else {
                        @new.push: “[$after<state>] $str”
                    }
                } else {
                    if is-half-resolved($before, $after) {
                        @half-resolved.push: “[testneeded] $str”;
                    } else {
                        @updated.push: “[$before<state>→$after<state>] $str”
                    }
                }
            }
        } elsif is-half-resolved($before, $after) {
            @half-resolved.push: “[testneeded] $str”
        } elsif $before<updated_at> ne $after<updated_at> {
            @updated.push: “[updated] $str”
        }
    }
    take “From ≈{$before-dir.basename} to ≈{$after-dir.basename}<br>”.trans: ‘_’ => ‘T’;

    take “Open tickets before: **{+%before.values.grep: *<is-open>}**<br>”;
    take “Open tickets after: **{  +%after.values.grep: *<is-open>}**<br>”;

    my @sections = (
        ‘Resolved tickets’             => @resolved,
        ‘Half-resolved (tests needed)’ => @half-resolved,
        ‘Updated tickets’              => @updated,
        ‘All new tickets’              => @new,
    );

    my $touched = +@sections.map(*.value).flat.unique;
    take “Number of tickets touched: **$touched**”;

    for @sections {
        take ‘’;
        take ‘’;
        take “## {.key} ({+.value})”;
        take ‘’;
        take ‘<pre>’;
        take $_ for @(autopad .value);
        take ‘</pre>’;
    }
}


my %*BOT-ENV;

Reportable.new.selfrun: ‘reportable6’, [ / report6? <before ‘:’> /,
                                           fuzzy-nick(‘reportable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

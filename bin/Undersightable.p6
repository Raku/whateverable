#!/usr/bin/env perl6
# Copyright © 2018
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
use Whateverable::Replaceable;

use Cro::HTTP::Client;
use Digest::SHA256::Native;

# ↓ TODO move into the config file?

my @bots =
‘dalek’,
‘Geth’,
‘camelia’,
‘synopsebot’,

‘bisectable6’,
‘committable6’,
‘benchable6’,
‘evalable6’,
‘unicodable6’,
‘statisfiable6’,
‘bloatable6’,
‘quotable6’,
‘greppable6’,
‘coverable6’,
‘releasable6’,
‘nativecallable6’,
‘squashable6’,
‘reportable6’,
‘notable6’,
‘shareable6’,
# ‘undersightable6’, # itself

‘yoleaux’,
‘huggable’,
‘buggable’,
‘SourceBaby’,
# ‘Undercover’, # not on #perl6 (only #perl6-dev)
# ‘NeuralAnomaly’, # temporarily offline
‘ilbot3’,
‘ZofBot’,
‘ilogger2’,
‘perlbot’,
;

my @websites = <
perl6.org
design.perl6.org
doc.perl6.org
docs.perl6.org
examples.perl6.org
faq.perl6.org
modules.perl6.org
rakudo.perl6.org
tablets.perl6.org
testers.perl6.org

rakudo.org
moarvm.org

perl6.party
rakudo.party
fail.rakudo.party
toast.perl6.party

irc.perl6.org
irclog.perlgeek.de
irclog.perlgeek.de/perl6/today
irclog.perlgeek.de/perl6-dev/today
irclog.perlgeek.de/moarvm/today
colabti.org/irclogger/irclogger_log/perl6
colabti.org/irclogger/irclogger_logs/perl6

6lang.party
6lang.org
design.6lang.org
doc.6lang.org
docs.6lang.org
examples.6lang.org
faq.6lang.org
modules.6lang.org
rakudo.6lang.org
tablets.6lang.org
testers.6lang.org

perlfoundation.org
>; # TODO replace “6lang” if another name is chosen


my @files = # TODO uncomment rakudo.org when it stops being so slow,
            #      and also when rakudo stops segfaulting (issue #24)
#\(
#    title          => ‘Rakudo Releases (rakudo.org)’,
#    url-pattern    => {“http://rakudo.org/downloads/rakudo/rakudo-$_.tar.gz”},
#    path-pattern   => {“data/undersightable/rakudo/rakudo-$_.tar.gz”},
#    start-tag-date => ‘2009-02-01’,
#    repo           => ‘./data/rakudo-moar’,
#),
\(
    title          => ‘Rakudo Releases (perl.org)’,
    url-pattern    => {“https://rakudo.perl6.org/downloads/rakudo/rakudo-$_.tar.gz”},
    path-pattern   => {“data/undersightable/rakudo/rakudo-$_.tar.gz”},
    start-tag-date => ‘2009-02-01’,
    repo           => ‘./data/rakudo-moar’,
),
#\(
#    title          => ‘NQP Releases (rakudo.org)’,
#    url-pattern    => {“http://rakudo.org/downloads/nqp/nqp-$_.tar.gz”},
#    path-pattern   => {“data/undersightable/nqp/nqp-$_.tar.gz”},
#    start-tag-date => ‘2012-12-01’,
#    repo           => ‘./data/nqp’,
#),
\(
    title          => ‘NQP Releases (perl.org)’,
    url-pattern    => {“https://rakudo.perl6.org/downloads/nqp/nqp-$_.tar.gz”},
    path-pattern   => {“data/undersightable/nqp/nqp-$_.tar.gz”},
    start-tag-date => ‘2012-12-01’,
    repo           => ‘./data/nqp’,
),
\(
    title          => ‘MoarVM Releases (moarvm.org)’,
    url-pattern    => {“https://moarvm.org/releases/MoarVM-$_.tar.gz”},
    path-pattern   => {“data/undersightable/moarvm/MoarVM-$_.tar.gz”},
    start-tag-date => ‘2014-01-01’,
    repo           => ‘./data/moarvm’,
),
;

unit class Undersightable does Whateverable;

also does Whateverable::Replaceable; # steal the logic to track online users

method help($msg) {
    “Like this: {$msg.server.current-nick}: check”
}

role Error   {}
role Warning {}
role Info    {}

sub get($url, $type? = Warning) {
    my $chr = $type ~~ Warning ?? ‘⚠’ !! ‘☠’;
    my $resp = await Cro::HTTP::Client.get: $url;
    CATCH {
        when X::Cro::HTTP::Error {
            take “| **$url** | **{.response.status}** | **$chr {.message}** |” does $type
        }
        default {
            take “| **$url** | **N/A** | **$chr {.message}** |” does $type
        }
    }
    $resp
}

sub check-websites {
    take “\n## Websites\n”;
    take ‘| URL | Status code | Message |’;
    take ‘|-----|-------------|---------|’;
    for @websites XR~ <https:// http://> -> $url {
        my $resp = get $url;
        take “| $url | {.status} | OK |” with $resp
    }
}

method check-files(:$title, :$url-pattern, :$path-pattern, :$start-tag-date, :$repo) {
    take “\n## $title\n”;
    take ‘| URL | Status code | Message |’;
    take ‘|-----|-------------|---------|’;
    for reverse get-tags $start-tag-date, :dups, :default(), :$repo {
        my $url =  $url-pattern($_);
        my $resp = get $url, Error;
        if $resp {
            my $path = $path-pattern($_).IO;
            mkdir $path.parent;
            if $path.e {
                my $x = await $resp.body;
                my $local-sha  = sha256-hex slurp :bin, $path;
                my $remote-sha = sha256-hex $x;
                if $local-sha eq $remote-sha {
                    take “| $url | $resp.status() | OK (same file as before) |”
                } else {
                    take “| $url | $resp.status() | **☠ File was changed after publication!** |”
                }
            } else {
                take “| $url | $resp.status() | OK (fresh download) |” but Info;
                spurt $path, await $resp.body;
            }
        }
    }
}

method check-releases {
    my $debug-date = Date.today.earlier(:5month);
    for @files {
        self.check-files: |$_, |(%*ENV<DEBUGGABLE>
                                 ?? :start-tag-date($debug-date) !! Empty)
    }
}

method check-bots($msg) {
    my %users = await self.list-users: $msg, %*ENV<DEBUGGABLE> ?? $CONFIG<cave> !! ‘#perl6’;
    take “\n## IRC Bots\n”;
    take ‘| Bot | Status |’;
    take ‘|-----|--------|’;
    for @bots {
        if %users{$_}:exists {
            take “| $_ | Online |”
        } else {
            take “| $_ | **⚠ Offline** |” does Warning
        }
    }
}

method check-version-mentions() {
    take “\n## Release announcements\n”;
    take ‘| URL | Status code | Message |’;
    take ‘|-----|-------------|---------|’;

    {
        my $url = ‘https://moarvm.org/’;
        my $last-tag = get-tags(‘2009-02-01’, :default(), repo => ‘./data/moarvm’).tail;
        my $resp = get $url;
        with $resp {
            if await($resp.body).contains: “The MoarVM team is proud to release version $last-tag” {
                take “| $url | {.status} | $last-tag release is mentioned |” ;
            } else {
                take “| $url | {.status} | **☠ No mention of $last-tag release found** |” does Error;
            }
        }
    }
    {
        my $url = ‘https://en.wikipedia.org/wiki/MoarVM’;
        my $last-tag = get-tags(‘2009-02-01’, :default(), repo => ‘./data/moarvm’).tail;
        my $resp = get $url;
        with $resp {
            if await($resp.body).match: / $last-tag / { # TODO better pattern
                take “| $url | {.status} | $last-tag release is mentioned |” ;
            } else {
                take “| $url | {.status} | **☠ No mention of $last-tag release found** |” does Error;
            }
        }
    }
    {
        my $url = ‘https://en.wikipedia.org/wiki/Rakudo_Perl_6’;
        my $last-tag = get-tags(‘2009-02-01’, :default(), repo => ‘./data/rakudo-moar’).tail;
        my $resp = get $url;
        with $resp {
            if await($resp.body).match: / [‘#’\d+ \s]? ‘"’$last-tag‘"’ / {
                take “| $url | {.status} | $last-tag release is mentioned |” ;
            } else {
                take “| $url | {.status} | **☠ No mention of $last-tag release found** |” does Error;
            }
        }
    }
}

multi method irc-to-me($msg where /check|status|info|test|log/) {
    $msg.reply: ‘OK! Working on it…’;
    start {
        my @jobs = (
            { gather check-websites },
            { gather self.check-releases },
            { gather self.check-bots($msg) },
            { gather self.check-version-mentions },
        );
        my @results  = @jobs.hyper(:1batch).map({ .().eager }).flat;
        my $warnings = +@results.grep: Warning;
        my $errors   = +@results.grep: Error;
        my $peek     = “{s $errors, ‘error’}, {s $warnings, ‘warning’}”;
        my $gist     = join “\n”, @results;
        (‘’ but FileStore(‘result.md’ => $gist)) but PrettyLink({“$peek: $_”})
    }
}


my %*BOT-ENV;

Undersightable.new.selfrun: ‘undersightable6’, [ fuzzy-nick(‘undersightable6’, 3) ]

# vim: expandtab shiftwidth=4 ft=perl6

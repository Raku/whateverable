#!/usr/bin/env raku
# Copyright © 2016-2023
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

use Whateverable;
use Whateverable::Bisection;
use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Config;
use Whateverable::Messages;
use Whateverable::Output;
use Whateverable::Processing;
use Whateverable::Running;

use File::Directory::Tree;
use File::Temp;
use IRC::Client;
use Terminal::ANSIColor;

unit class Bisectable does Whateverable;

method help($msg) {
    “Like this: {$msg.server.current-nick}”
    ~ ‘: old=2015.12 new=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4’ # TODO better example
}

sub autobisect($msg, $code) {
    my $start-time = now;
    my $config = ‘6c’;
    my @commits = get-commits $config;
    my $file = process-code $code, $msg;

    constant TOTAL-TIME = 60 × 15;
    my @outputs; # unlike %shas this is ordered
    my %shas;    # { output => [sha, sha, …], … }

    # This feature differs from committable because it does *not*
    # intermingle the results!
    proccess-and-group-commits @outputs, %shas, $file,
                               @commits,
                               :!intermingle, :!prepend,
                               :$start-time, time-limit => TOTAL-TIME;

    reply $msg, commit-groups-to-gisted-reply(@outputs, %shas, $config)
                but PrettyLink({ “Output on all releases: $_” });
    sleep 1; # OK this kinda sucks but otherwise the order can be wrong
    # The magic begins now 🪄
    return ‘Nothing to bisect!’ if @outputs == 1;
    my $changes-limit = 3;
    if @outputs - 1 > $changes-limit {
        return “More than $changes-limit changes to bisect, ”
        ~ “please try a narrower range like old={%shas{@outputs[*-2]}.tail} new=HEAD”
    }
    start {
        my @sha-gatherer;
        for @outputs.rotor(2 => -1).reverse -> ($from, $to) {
            my $from-sha = %shas{$from}.tail;
            my   $to-sha = %shas{  $to}.head;
            $to-sha = ‘HEAD’ if $to-sha.starts-with: ‘HEAD(’; # total hack but it works
            try { # we need to handle it and move forward
                process $msg, $code, $from-sha, $to-sha, @sha-gatherer; # bisect!
                CATCH { default { handle-exception $_, $msg } }
            }
        }
        my $outputs-before = +@outputs;
        for @sha-gatherer {
            my $short = get-short-commit $_;
            proccess-and-group-commits @outputs, %shas, $file,
                                       $short ~ ‘^’,
                                       :intermingle, :!prepend,
                                       :$start-time, time-limit => TOTAL-TIME;
            proccess-and-group-commits @outputs, %shas, $file,
                                       $short,
                                       :intermingle, :prepend,
                                       :$start-time, time-limit => TOTAL-TIME;
        }
        if @outputs ≠ $outputs-before {
            # Ideally all commits will fall into one of the
            # existing categories that were created by running
            # the code on releases. If we find new output it
            # simply means the behavior changed multiple times
            # between two releases, and people should interpret
            # the results manually and rerun on different
            # endpoints if necessary.
            reply $msg, ‘⚠ New output detected, please review the results manually’;
        }
        LEAVE .unlink with $file; # XXX we have to do it here…
        reply $msg, commit-groups-to-gisted-reply(@outputs, %shas, $config)
                    but PrettyLink({ “Output on all releases and bisected commits: $_” });
        Nil
    }
}

my regex spaceeq { \s* ‘=’ \s* | \s+ }
my regex delim   { \s* [ ‘,’ \s* ]?  }
my regex bisect-cmd { :i
    ^ \s*
    [
        [ [old|good] <&spaceeq> $<old>=<-[\s,]>+ <&delim> ]
        [ [new|bad]  <&spaceeq> $<new>=\S+       \s*      ]?
        |
        [ [new|bad]  <&spaceeq> $<new>=<-[\s,]>+ <&delim> ]?
        [ [old|good] <&spaceeq> $<old>=\S+       \s*      ]?
    ]
    $<code>=[
        [ [ $<maybe-rev>=<-[\s,]>+
            <?{so to-full-commit $<maybe-rev>.tail}> ]**1..2 % <&delim>
          \s+
        ]?
        $<maybe-code>=.*
    ]
    $
}

multi method irc-to-me($msg where .text ~~ &bisect-cmd) {
    my $old  = $<old> // ‘2015.12’;
    my $new  = $<new> // ‘HEAD’;
    my $code = $<code>;
    if !$<old>.defined and !$<new>.defined {
        if $<maybe-rev> {
            $old  =         $<maybe-rev>[0];
            $new  = $_ with $<maybe-rev>[1];
            $code = $<maybe-code>;
            reply $msg, “Using old=$old new=$new in an attempt to do what you mean”
        } else {
            reply $msg, ‘Will bisect the whole range automagically because no endpoints were provided, hang tight’;
            return autobisect $msg, $code
        }
    }
    process $msg, ~$code, ~$old, ~$new
}

sub process($msg, $code, $old, $new, @sha-gatherer?) {
    # convert to real ids so we can look up the builds
    my @options = <HEAD>;
    my $full-old = to-full-commit $old;
    without $full-old {
        grumble “Cannot find revision “$old””
        ~ “ (did you mean “{get-short-commit get-similar $old, @options}”?)”
    }
    grumble “No build for revision “$old”” unless build-exists $full-old;
    my $short-old = get-short-commit $old eq $full-old | ‘HEAD’ ?? $full-old !! $old;

    my $full-new = to-full-commit $new;
    without $full-new {
        grumble “Cannot find revision “$new””
        ~ “ (did you mean “{get-short-commit get-similar $new, @options}”?)”
    }
    grumble “No build for revision “$new”” unless build-exists $full-new;
    my $short-new = get-short-commit $new eq ‘HEAD’ ?? $full-new !! $new;

    my $code-file = process-code $code, $msg;
    LEAVE .unlink with $code-file;

    my $old-result = run-snippet $full-old, $code-file;
    my $new-result = run-snippet $full-new, $code-file;

    grumble “Problem with $short-old commit: $old-result<output>” if $old-result<signal> < 0;
    grumble “Problem with $short-new commit: $new-result<output>” if $new-result<signal> < 0;

    if $old-result<exit-code> == 125 {
        grumble ‘Exit code on “old” revision is 125,’
        ~ ‘ which means skip this commit. Please try another old revision’
    }
    if $new-result<exit-code> == 125 {
        grumble ‘Exit code on “new” revision is 125,’
        ~ ‘ which means skip this commit. Please try another new revision’
    }

    $old-result<output> //= ‘’;
    $new-result<output> //= ‘’;

    if  $old-result<exit-code>   == $new-result<exit-code>
    and $old-result<signal>      == $new-result<signal>
    and $old-result<output>      eq $new-result<output>    {
        if $old-result<signal> ≠ 0 {
            reply $msg, “On both starting points (old=$short-old new=$short-new)”
            ~ “ the exit code is $old-result<exit-code>,”
            ~ “ exit signal is {signal-to-text $old-result<signal>}”
            ~ ‘ and the output is identical as well’
        } else {
            reply $msg, “On both starting points (old=$short-old new=$short-new)”
            ~ “ the exit code is $old-result<exit-code>”
            ~ ‘ and the output is identical as well’
        }
        grumble “Output on both points: «$old-result<output>»” # will be gisted automatically if required
    }

    my $repo-cwd = tempdir :!unlink;
    LEAVE { rmtree $_ with $repo-cwd }
    run :out(Nil), :err(Nil), <git clone>, $CONFIG<projects><rakudo-moar><repo-path>, $repo-cwd; # TODO check the result

    my $bisect-start = get-output cwd => $repo-cwd, <git bisect start>;
    my $bisect-old   = get-output cwd => $repo-cwd, <git bisect old>, $full-old;
    grumble ‘Failed to run ｢bisect start｣’  if $bisect-start<exit-code> ≠ 0;
    grumble ‘Failed to run ｢bisect old …”｣’ if $bisect-old<exit-code>   ≠ 0;

    my $init-result = get-output cwd => $repo-cwd, <git bisect new>, $full-new;
    if $init-result<exit-code> ≠ 0 {
        reply $msg, ‘bisect log: ’ ~ upload { query  => $msg.text,
                                              result => colorstrip($init-result<output>), },
                                            description => $msg.server.current-nick,
                                            public => !%*ENV<DEBUGGABLE>;
        grumble ‘bisect init failure. See the log for more details’
    }
    my $bisect-result;
    if $old-result<signal> ≠ $new-result<signal> { # Signal
        reply $msg, “Bisecting by exit signal (old=$short-old new=$short-new).”
                  ~ “ Old exit signal: {signal-to-text $old-result<signal>}”;
        $bisect-result = run-bisect :$repo-cwd, :$code-file,
                                    old-exit-signal => $old-result<signal>
    } elsif $old-result<exit-code> ≠ $new-result<exit-code> { # Exit code
        reply $msg, “Bisecting by exit code (old=$short-old new=$short-new).”
                        ~ “ Old exit code: $old-result<exit-code>”;
        $bisect-result = run-bisect :$repo-cwd, :$code-file,
                                    old-exit-code => $old-result<exit-code>
    } else { # Output
        if $old-result<signal> ≠ 0 {
            reply $msg, “Bisecting by output (old=$short-old new=$short-new)”
            ~ “ because on both starting points”
            ~ “ the exit code is $old-result<exit-code>”
            ~ “ and exit signal is {signal-to-text $old-result<signal>}”
        } else {
            reply $msg, “Bisecting by output (old=$short-old new=$short-new)”
            ~ “ because on both starting points”
            ~ “ the exit code is $old-result<exit-code>”
        }
        $bisect-result = run-bisect :$repo-cwd, :$code-file,
                                     old-output => $old-result<output>
    }

    my $bisect-status = $bisect-result<status>;
    my $bisect-output = $bisect-result<log>;

    reply $msg, ‘bisect log: ’ ~ upload { ‘query’   => $msg.text,
                                          ‘result’  => colorstrip(“$init-result<output>\n$bisect-output”), },
                                        description => $msg.server.current-nick,
                                        public => !%*ENV<DEBUGGABLE>;

    if $bisect-result<first-new-commit>.list > 1 {
        grumble “There are {+$bisect-result<first-new-commit>} candidates for the”
        ~ ‘ first “new” revision. See the log for more details’
    }
    if $bisect-status ≠ 0 {
        grumble ｢‘bisect run’ failure. See the log for more details｣
    }
    my $link-msg = get-output(:cwd($repo-cwd), <git show --quiet --date=short>,
                              “--pretty=(%cd) $CONFIG<bisectable><commit-link>/%H”,
                              ‘bisect/new’)<output>;
    reply $msg, $link-msg;
    if $link-msg.ends-with: ‘07fecb52eb1fd07397659f19a5cf36dc61f84053’ {
        grumble ‘The result looks a bit unrealistic. Most probably the output’
        ~ ‘ is different on every commit (e.g. ｢bisect: say rand｣)’
    }
    .push: $bisect-result<first-new-commit> with @sha-gatherer;
    LEAVE sleep 0.02;
    Nil
}


Bisectable.new.selfrun: ‘bisectable6’, [ / [ b[isect]?6? | ‘what’ ] <before ‘:’> /,
                                         fuzzy-nick(‘bisectable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

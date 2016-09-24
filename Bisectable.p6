#!/usr/bin/env perl6
# Copyright © 2016
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
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

use lib ‘.’;
use Whateverable;

use File::Temp;
use File::Directory::Tree;
use IRC::Client;

unit class Bisectable is Whateverable;

constant LINK          = ‘https://github.com/rakudo/rakudo/commit’;
constant BUILD-LOCK    = ‘./lock’.IO.absolute;

enum RevisionType <Old New Skip>;

method help($message) {
    ~ “Like this: {$message.server.current-nick}”
    ~ ‘: old=2015.12 new=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT128181’
}

sub signal-to-text($signal) {
    “$signal ({Signal($signal) // ‘None’})”
}

method run-bisect($code-file, *%_ (:$old-exit-code, :$old-exit-signal, :$old-output) ) {
    my ($output, $status);
    my @bisect-log = gather loop {
        my $revision-type = self.test-commit($code-file, |%_);
        ($output, $status) = self.get-output(‘git’, ‘bisect’, $revision-type.lc);
        last if $output ~~ /^^ \S+ ‘ is the first new commit’ /; # TODO just return this
        LAST take $output;
    }
    return @bisect-log.join(“\n”), $status
}

method test-commit($code-file, :$old-exit-code, :$old-exit-signal, :$old-output) {
    my ($current-commit,) = self.get-output('git', 'rev-parse', 'HEAD');

    # looks a bit nicer this way
    LEAVE take ‘»»»»» -------------------------------------------------------------------------’;

    take “»»»»» Testing $current-commit”;
    if not self.build-exists($current-commit) {
        take ‘»»»»» Build does not exist, skip this commit’;
        return Skip # skip non-existent builds
    }

    my ($output, $exit-code, $exit-signal) = self.run-snippet($current-commit, $code-file);
    if $exit-signal < 0 {
        take “»»»»» Cannot test this commit. Reason: $output”;
        take ‘»»»»» Therefore, skipping this revision’;
        return Skip # skip failed builds
    }

    take ‘»»»»» Script output:’;
    take $output;
    take “»»»»» Script exit code: $exit-code”;
    take “»»»»» Script exit signal: {signal-to-text $exit-signal}” if $exit-signal;

    if $exit-code == 125 {
        take ‘»»»»» Exit code 125 means “skip”’;
        take ‘Therefore, skipping this revision as you requested’;
        return Skip # somebody did “exit 125” in his code on purpose
    }

    # compare signals
    if defined $old-exit-signal {
        my $revision-type = $exit-signal == $old-exit-signal ?? Old !! New;
        take ‘»»»»» Bisecting by exit signal’;
        take “»»»»» Current exit signal is {signal-to-text $exit-signal}, exit signal on “old” revision is {signal-to-text $old-exit-signal}”;
        if $old-exit-signal != 0 {
            take “»»»»» Note that on “old” revision exit signal is normally {signal-to-text 0}, you are probably trying to find when something was fixed”;
        }
        take ‘»»»»» If exit signal is not the same as on “old” revision, this revision will be marked as “new”’;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # compare exit code (typically like a normal ｢git bisect run …｣)
    if defined $old-exit-code {
        my $revision-type = $exit-code == $old-exit-code ?? Old !! New;
        take ‘»»»»» Bisecting by exit code’;
        take “»»»»» Current exit code is $exit-code, exit code on “old” revision is $old-exit-code”;
        if $old-exit-code != 0 {
            take ‘»»»»» Note that on “old” revision exit code is normally 0, you are probably trying to find when something was fixed’;
        }
        take ‘»»»»» If exit code is not the same as on “old” revision, this revision will be marked as “new”’;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # compare the output
    if defined $old-output {
        my $revision-type = $output eq $old-output ?? Old !! New;
        take ‘»»»»» Bisecting by output’;
        take ‘»»»»» Output on “old” revision is:’;
        take $old-output;
        take “»»»»» The output is {$revision-type == Old ?? ‘identical’ !! ‘different’}”;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # This should not happen.
    # TODO can we avoid this piece of code somehow?
    take ‘»»»»» Internal bisectable error. This should not happen. Please contact the maintainers.’;
    take ‘»»»»» Therefore, skipping this revision’;
    return Skip
}

my regex spaceeq { \s* ‘=’ \s* | \s+ }
my regex bisect-cmd {
    ^ \s*
    [
        [ [old|good] <spaceeq> $<old>=\S+ \s* ]
        [ [new|bad]  <spaceeq> $<new>=\S+ \s* ]?
        |
        [ [new|bad]  <spaceeq> $<new>=\S+ \s* ]?
        [ [old|good] <spaceeq> $<old>=\S+ \s* ]?
    ]
    $<code>=.*
    $
}

multi method irc-to-me($message where { .text !~~ /:i ^ [help|source|url] ‘?’? $ | ^stdin /
                                        # ↑ stupid, I know. See RT #123577
                                        and .text ~~ &bisect-cmd}) {
    my $value = self.process($message, ~$<code>,
                             ~($<old> // ‘2015.12’), ~($<new> // ‘HEAD’));
    return ResponseStr.new(:$value, :$message);
}

method process($message, $code is copy, $old, $new) {
    my ($succeeded, $code-response) = self.process-code($code, $message);
    return $code-response unless $succeeded;
    $code = $code-response;

    # convert to real ids so we can look up the builds
    my $full-old = self.to-full-commit($old);
    return “Cannot find revision “$old””  unless           defined($full-old);
    return “No build for revision “$old”” unless self.build-exists($full-old);
    my $short-old = self.get-short-commit($old eq $full-old | 'HEAD' ?? $full-old !! $old);

    my $full-new = self.to-full-commit($new);
    return “Cannot find revision “$new””  unless           defined($full-new);
    return “No build for revision “$new”” unless self.build-exists($full-new);
    my $short-new = self.get-short-commit($new eq ‘HEAD’ ?? $full-new !! $new);

    my $filename = self.write-code($code);

    my $old-dir = $*CWD;
    chdir RAKUDO;
    my ($old-output, $old-exit-code, $old-exit-signal,) = self.run-snippet($full-old, $filename);
    my ($new-output, $new-exit-code, $new-exit-signal,) = self.run-snippet($full-new, $filename);
    chdir $old-dir;

    return “Problem with $short-old commit: $old-output” if $old-exit-signal < 0;
    return “Problem with $short-new commit: $new-output” if $new-exit-signal < 0;

    if $old-exit-code == 125 {
        return ‘Exit code on “old” revision is 125, which means skip this commit. Please try another old revision’;
    }
    if $new-exit-code == 125 {
        return ‘Exit code on “new” revision is 125, which means skip this commit. Please try another new revision’;
    }

    $old-output //= ‘’;
    $new-output //= ‘’;

    if  $old-exit-code   == $new-exit-code
    and $old-exit-signal == $new-exit-signal
    and $old-output      eq $new-output      {
        if $old-exit-signal != 0 {
            $message.reply: “On both starting points (old=$short-old new=$short-new) the exit code is $old-exit-code, exit signal is {signal-to-text $old-exit-signal} and the output is identical as well”;
        } else {
            $message.reply: “On both starting points (old=$short-old new=$short-new) the exit code is $old-exit-code and the output is identical as well”;
        }
        return “Output on both points: $old-output”; # will be gisted automatically if required
    }

    my $dir = tempdir :!unlink;
    run(‘git’, ‘clone’, RAKUDO, $dir);
    chdir $dir;

    self.get-output(‘git’, ‘bisect’, ‘start’);
    self.get-output(‘git’, ‘bisect’, ‘old’, $full-old);
    my ($init-output, $init-status) = self.get-output(‘git’, ‘bisect’, ‘new’, $full-new);
    if $init-status != 0 {
        $message.reply: ‘bisect log: ’ ~ self.upload({ ‘query’       => $message.text,
                                                       ‘result’      => $init-output, },
                                                     description => $message.server.current-nick);
        return ‘bisect init failure’;
    }
    my ($bisect-output, $bisect-status);
    if $old-exit-signal != $new-exit-signal {
        $message.reply: “Bisecting by exit signal (old=$short-old new=$short-new). Old exit signal: {signal-to-text $old-exit-signal}”;
        ($bisect-output, $bisect-status) = self.run-bisect($filename, :$old-exit-signal);
    } elsif $old-exit-code != $new-exit-code {
        $message.reply: “Bisecting by exit code (old=$short-old new=$short-new). Old exit code: $old-exit-code”;
        ($bisect-output, $bisect-status) = self.run-bisect($filename, :$old-exit-code);
    } else {
        if $old-exit-signal != 0 {
            $message.reply: “Bisecting by output (old=$short-old new=$short-new) because on both starting points the exit code is $old-exit-code and exit signal is {signal-to-text $old-exit-signal}”;
        } else {
            $message.reply: “Bisecting by output (old=$short-old new=$short-new) because on both starting points the exit code is $old-exit-code”;
        }
        ($bisect-output, $bisect-status) = self.run-bisect($filename, :$old-output);
    }
    $message.reply: ‘bisect log: ’ ~ self.upload({ ‘query’       => $message.text,
                                                   ‘result’      => “$init-output\n$bisect-output”, },
                                                 description => $message.server.current-nick);

    if $bisect-status != 0 {
        return “‘bisect run’ failure”;
    } else {
        return self.get-output(‘git’, ‘show’, ‘--quiet’, ‘--date=short’, “--pretty=(%cd) {LINK}/%H”, ‘bisect/new’).first;
    }

    LEAVE {
        chdir  $old-dir  if defined $old-dir;
        unlink $filename if defined $filename and $filename.chars > 0;
        rmtree $dir      if defined $dir      and $dir.chars      > 0;
        sleep 0.02; # otherwise the output may be in the wrong order TODO is it a problem in IRC::Client?
    }
}

Bisectable.new.selfrun(‘bisectable6’, [ /bisect6?/, fuzzy-nick(‘bisectable6’, 2) ]);

# vim: expandtab shiftwidth=4 ft=perl6

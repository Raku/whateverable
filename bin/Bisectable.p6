#!/usr/bin/env perl6
# Copyright © 2016-2017
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
use Misc;

use File::Directory::Tree;
use File::Temp;
use IRC::Client;
use Terminal::ANSIColor;

unit class Bisectable does Whateverable;

constant COMMIT-LINK = ‘https://github.com/rakudo/rakudo/commit’;
constant BUILD-LOCK  = ‘./lock’.IO.absolute;
constant TRIM-CHARS  = 2000;

enum RevisionType <Old New Skip>;

method help($msg) {
    “Like this: {$msg.server.current-nick}”
    ~ ‘: old=2015.12 new=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4’ # TODO better example
}

method run-bisect($code-file, *%_ (:$old-exit-code, :$old-exit-signal, :$old-output, :$cwd) ) {
    my $status;
    my @bisect-log = gather loop {
        my $revision-type = self.test-commit: :$cwd, $code-file, |%_;
        my $result = get-output :$cwd, ‘git’, ‘bisect’, $revision-type.lc;
        $status = $result<exit-code>;
        last if $result<output> ~~ /^^ \S+ ‘ is the first new commit’ /; # TODO just return this
        last if $result<exit-code> ≠ 0;
        LAST take $result<output>
    }
    return @bisect-log.join(“\n”), $status
}

method test-commit($code-file, :$old-exit-code, :$old-exit-signal, :$old-output, :$cwd) {
    my $current-commit = get-output(:$cwd, ‘git’, ‘rev-parse’, ‘HEAD’)<output>;

    LEAVE take “»»»»» {‘-’ x 73}”; # looks a bit nicer this way

    take “»»»»» Testing $current-commit”;
    if not self.build-exists: $current-commit {
        take ‘»»»»» Build does not exist, skip this commit’;
        return Skip # skip non-existent builds
    }

    my $result = self.run-snippet: $current-commit, $code-file;
    if $result<exit-code> < 0 { # TODO use something different
        take “»»»»» Cannot test this commit. Reason: $result<output>”;
        take ‘»»»»» Therefore, skipping this revision’;
        return Skip # skip failed builds
    }

    take ‘»»»»» Script output:’;
    my $short-output = shorten $result<output>, TRIM-CHARS;
    take $short-output;
    take “»»»»» (output was trimmed  because it is too large)” if $short-output ne $result<output>;

    take “»»»»» Script exit code: $result<exit-code>”;
    take “»»»»» Script exit signal: {signal-to-text $result<signal>}” if $result<signal>;

    if $result<exit-code> == 125 {
        take ‘»»»»» Exit code 125 means “skip”’;
        take ‘Therefore, skipping this revision as you requested’;
        return Skip # somebody did “exit 125” in his code on purpose
    }

    # compare signals
    with $old-exit-signal {
        take ‘»»»»» Bisecting by exit signal’;
        take “»»»»» Current exit signal is {signal-to-text $result<signal>}, exit signal on “old” revision is {signal-to-text $old-exit-signal}”;
        if $old-exit-signal ≠ 0 {
            take “»»»»» Note that on “old” revision exit signal is normally {signal-to-text 0}, you are probably trying to find when something was fixed”
        }
        take ‘»»»»» If exit signal is not the same as on “old” revision, this revision will be marked as “new”’;
        my $revision-type = $result<signal> == $old-exit-signal ?? Old !! New;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # compare exit code (typically like a normal ｢git bisect run …｣)
    with $old-exit-code {
        take ‘»»»»» Bisecting by exit code’;
        take “»»»»» Current exit code is $result<exit-code>, exit code on “old” revision is $old-exit-code”;
        if $old-exit-code ≠ 0 {
            take ‘»»»»» Note that on “old” revision exit code is normally 0, you are probably trying to find when something was fixed’
        }
        take ‘»»»»» If exit code is not the same as on “old” revision, this revision will be marked as “new”’;
        my $revision-type = $result<exit-code> == $old-exit-code ?? Old !! New;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # compare the output
    with $old-output {
        take ‘»»»»» Bisecting by output’;
        take ‘»»»»» Output on “old” revision is:’;
        take $old-output;
        my $revision-type = $result<output> eq $old-output ?? Old !! New;
        take “»»»»» The output is {$revision-type == Old ?? ‘identical’ !! ‘different’}”;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # This should not happen.
    die ‘Internal bisectable error. This should not happen.’
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
    $<code>=.*
    $
}

multi method irc-to-me($msg where .text ~~ &bisect-cmd) {
    self.process: $msg, ~$<code>,
                  ~($<old> // ‘2015.12’),
                  ~($<new> // ‘HEAD’)
}

method process($msg, $code is copy, $old, $new) {
    $code = self.process-code: $code, $msg;

    # convert to real ids so we can look up the builds
    my @options = <HEAD>;
    my $full-old = to-full-commit $old;
    without $full-old {
        grumble “Cannot find revision “$old””
        ~ “ (did you mean “{self.get-short-commit: self.get-similar: $old, @options}”?)”
    }
    grumble “No build for revision “$old”” unless self.build-exists: $full-old;
    my $short-old = self.get-short-commit: $old eq $full-old | ‘HEAD’ ?? $full-old !! $old;

    my $full-new = to-full-commit $new;
    without $full-new {
        grumble “Cannot find revision “$new””
        ~ “ (did you mean “{self.get-short-commit: self.get-similar: $new, @options}”?)”
    }
    grumble “No build for revision “$new”” unless self.build-exists: $full-new;
    my $short-new = self.get-short-commit: $new eq ‘HEAD’ ?? $full-new !! $new;

    my $filename = self.write-code: $code;
    LEAVE { unlink $_ with $filename }

    my $old-result = self.run-snippet: $full-old, $filename;
    my $new-result = self.run-snippet: $full-new, $filename;

    grumble “Problem with $short-old commit: $old-result<output>” if $old-result<signal> < 0;
    grumble “Problem with $short-new commit: $new-result<output>” if $new-result<signal> < 0;

    if $old-result<exit-code> == 125 {
        grumble ‘Exit code on “old” revision is 125, which means skip this commit. Please try another old revision’
    }
    if $new-result<exit-code> == 125 {
        grumble ‘Exit code on “new” revision is 125, which means skip this commit. Please try another new revision’
    }

    $old-result<output> //= ‘’;
    $new-result<output> //= ‘’;

    if  $old-result<exit-code>   == $new-result<exit-code>
    and $old-result<signal>      == $new-result<signal>
    and $old-result<output>      eq $new-result<output>    {
        if $old-result<signal> ≠ 0 {
            $msg.reply: “On both starting points (old=$short-old new=$short-new) the exit code is $old-result<exit-code>, exit signal is {signal-to-text $old-result<signal>} and the output is identical as well”
        } else {
            $msg.reply: “On both starting points (old=$short-old new=$short-new) the exit code is $old-result<exit-code> and the output is identical as well”
        }
        grumble “Output on both points: «$old-result<output>»” # will be gisted automatically if required
    }

    my $dir = tempdir :!unlink;
    LEAVE { rmtree $_ with $dir }
    run :out(Nil), :err(Nil), ‘git’, ‘clone’, $RAKUDO, $dir; # TODO check the result

    my $bisect-start = get-output cwd => $dir, ‘git’, ‘bisect’, ‘start’;
    my $bisect-old   = get-output cwd => $dir, ‘git’, ‘bisect’, ‘old’, $full-old;
    grumble ‘Failed to run ｢bisect start｣’  if $bisect-start<exit-code> ≠ 0;
    grumble ‘Failed to run ｢bisect old …”｣’ if $bisect-old<exit-code>   ≠ 0;

    my $init-result = get-output cwd => $dir, ‘git’, ‘bisect’, ‘new’, $full-new;
    if $init-result<exit-code> ≠ 0 {
        $msg.reply: ‘bisect log: ’ ~ self.upload: { query  => $msg.text,
                                                    result => colorstrip($init-result<output>), },
                                                  description => $msg.server.current-nick,
                                                  public => !%*ENV<DEBUGGABLE>;
        grumble ‘bisect init failure. See the log for more details’
    }
    my ($bisect-output, $bisect-status);
    if $old-result<signal> ≠ $new-result<signal> {
        $msg.reply: “Bisecting by exit signal (old=$short-old new=$short-new). Old exit signal: {signal-to-text $old-result<signal>}”;
        ($bisect-output, $bisect-status) = self.run-bisect: cwd => $dir, $filename, :old-exit-signal($old-result<signal>)
    } elsif $old-result<exit-code> ≠ $new-result<exit-code> {
        $msg.reply: “Bisecting by exit code (old=$short-old new=$short-new). Old exit code: $old-result<exit-code>”;
        ($bisect-output, $bisect-status) = self.run-bisect: cwd => $dir, $filename, :old-exit-code($old-result<exit-code>)
    } else {
        if $old-result<signal> ≠ 0 {
            $msg.reply: “Bisecting by output (old=$short-old new=$short-new) because on both starting points the exit code is $old-result<exit-code> and exit signal is {signal-to-text $old-result<signal>}”
        } else {
            $msg.reply: “Bisecting by output (old=$short-old new=$short-new) because on both starting points the exit code is $old-result<exit-code>”
        }
        ($bisect-output, $bisect-status) = self.run-bisect: cwd => $dir, $filename, :old-output($old-result<output>)
    }
    $msg.reply: ‘bisect log: ’ ~ self.upload: { ‘query’   => $msg.text,
                                                ‘result’  => colorstrip(“$init-result<output>\n$bisect-output”), },
                                              description => $msg.server.current-nick,
                                              public => !%*ENV<DEBUGGABLE>;

    if $bisect-status == 2 {
        my $good-revs     = get-output(:cwd($dir), ‘git’, ‘for-each-ref’,
                                       ‘--format=%(objectname)’, ‘refs/bisect/old-*’)<output>;
        my @possible-revs = get-output(:cwd($dir), ‘git’, ‘rev-list’,
                                       ‘refs/bisect/new’, ‘--not’, |$good-revs.lines)<output>.lines;
        grumble “There are {+@possible-revs} candidates for the first “new” revision. See the log for more details”
    }
    if $bisect-status ≠ 0 {
        grumble ｢‘bisect run’ failure. See the log for more details｣
    }
    my $link-msg = get-output(:cwd($dir), ‘git’, ‘show’, ‘--quiet’, ‘--date=short’,
                              “--pretty=(%cd) {COMMIT-LINK}/%H”, ‘bisect/new’)<output>;
    $msg.reply: $link-msg;
    if $link-msg.ends-with: ‘07fecb52eb1fd07397659f19a5cf36dc61f84053’ {
        grumble ‘The result looks a bit unrealistic, doesn't it? Most probably the output is different on every commit (e.g. ｢bisect: say rand｣)’
    }
    LEAVE sleep 0.02;
    Nil
}

Bisectable.new.selfrun: ‘bisectable6’, [ / [ b[isect]?6? | ‘what’ ] <before ‘:’> /,
                                         fuzzy-nick(‘bisectable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

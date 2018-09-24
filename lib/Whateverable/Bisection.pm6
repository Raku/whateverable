# Copyright © 2016-2018
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

use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Config;
use Whateverable::Output;
use Whateverable::Running;

unit module Whateverable::Bisection;

enum RevisionType is export <Old New Skip>;

#↓ Use this to bisect stuff across a bunch of builds
#↓ It can be used to bisect anything (not just Rakudo), it
#↓ all depends on what you provide in &runner and :$repo-cwd.
sub run-bisect(&runner  = &standard-runner,  #← Something to run on every revision
               &decider = &adaptive-decider, #← Something to classify the result from &runner
               :$skip-missing-builds = True, #← True to Skip if not build-exists
               :$repo-cwd,                   #← Repo path where we will run `git bisect`
               *%custom,                     #← Anything that may be needed in &runner or &decider
              ) is export {
    my $status;
    my $first-new-commit;

    my @bisect-log = gather loop {
        NEXT take “»»»»» {‘-’ x 73}”; # looks a bit nicer this way
        my $current-commit =  get-output(cwd => $repo-cwd,
                                         <git rev-parse HEAD>)<output>;
        take “»»»»» Testing $current-commit”;

        if $skip-missing-builds and not build-exists $current-commit {
            take ‘»»»»» Build does not exist, skip this commit’;
            return Skip # skip non-existent builds
        }

        my $run-result     = &runner(              :$current-commit, |%custom);
        my $revision-type  = &decider($run-result, :$current-commit, |%custom);
        my $result         = get-output cwd => $repo-cwd,
                                        <git bisect>, $revision-type.lc;
        $status = $result<exit-code>;
        if $result<output> ~~ /^^ (\S+) ‘ is the first new commit’ / {
            $first-new-commit = ~$0;
            last
        }
        if $status == 2 {
            my $good-revs     = get-output(:cwd($repo-cwd), <git for-each-ref>,
                                           ‘--format=%(objectname)’, ‘refs/bisect/old-*’)<output>;
            my @possible-revs = get-output(:cwd($repo-cwd), <git rev-list>,
                                           <refs/bisect/new --not>, |$good-revs.lines)<output>.lines;
            $first-new-commit = @possible-revs;
            last
        }
        last if $status ≠ 0;
        LAST take $result<output>
    }
    my $log = @bisect-log.join(“\n”);
    %( :$log, :$status, :$first-new-commit )
}

#↓ Runs a file containing a code snippet. Needs :$code-file custom arg.
sub standard-runner(:$current-commit!, :$code-file!, *%_) is export {
    run-snippet $current-commit, $code-file
}

#↓ Takes an output of run-snippet or get-output and uses it to decide
#↓ what to do. You must provide exactly one named
#↓ argument ($old-exit-code, $old-exit-signal, $old-output).
#↓ Generally it considers any deviation from $old-* to be the New
#↓ behavior, so effectively it finds the first change. Whether
#↓ that change is good or not is left for user discretion, here we
#↓ just work with Old / New / Skip concepts.
sub adaptive-decider($result,
                     :$current-commit,
                     :$old-exit-code,
                     :$old-exit-signal,
                     :$old-output,
                     *%_) is export {

    if $result<exit-code> < 0 { # TODO use something different. … like what?
        take “»»»»» Cannot test this commit. Reason: $result<output>”;
        take ‘»»»»» Therefore, skipping this revision’;
        return Skip # skip failed builds
    }

    take ‘»»»»» Script output:’;
    my $short-output = shorten $result<output>, $CONFIG<bisectable><trim-chars>;
    take $short-output;
    if $short-output ne $result<output> {
        take “»»»»» (output was trimmed  because it is too large)”
    }

    take “»»»»» Script exit code: $result<exit-code>”;
    take “»»»»» Script exit signal: {signal-to-text $result<signal>}”
        if $result<signal>;

    if $result<exit-code> == 125 {
        take ‘»»»»» Exit code 125 means “skip”’;
        take ‘Therefore, skipping this revision as you requested’;
        return Skip # somebody did “exit 125” in their code on purpose
    }

    # compare signals
    with $old-exit-signal {
        take ‘»»»»» Bisecting by exit signal’;
        take “»»»»» Current exit signal is {signal-to-text $result<signal>},”
          ~ “ exit signal on “old” revision is {signal-to-text $old-exit-signal}”;
        if $old-exit-signal ≠ 0 {
            take “»»»»» Note that on “old” revision exit signal is normally”
              ~ “ {signal-to-text 0}, you are probably trying”
              ~ “ to find when something was fixed”
        }
        take ‘»»»»» If exit signal is not the same as on “old” revision,’
          ~ ‘ this revision will be marked as “new”’;
        my $revision-type = $result<signal> == $old-exit-signal ?? Old !! New;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }

    # compare exit code (typically like a normal ｢git bisect run …｣)
    with $old-exit-code {
        take ‘»»»»» Bisecting by exit code’;
        take “»»»»» Current exit code is $result<exit-code>, ”
        ~ “exit code on “old” revision is $old-exit-code”;
        if $old-exit-code ≠ 0 {
            take ‘»»»»» Note that on “old” revision exit code is normally 0,’
            ~ ‘ you are probably trying to find when something was fixed’
        }
        take ‘»»»»» If exit code is not the same as on “old” revision,’
        ~ ‘ this revision will be marked as “new”’;
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
        take “»»»»» The output is {$revision-type == Old
                                   ?? ‘identical’ !! ‘different’}”;
        take “»»»»» Therefore, marking this revision as “{$revision-type.lc}””;
        return $revision-type
    }
}

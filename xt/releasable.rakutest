#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = ‘rakudo-mock’;

use lib <lib xt/lib>;
use File::Directory::Tree;
use IRC::Client;
use Test;
use Testable;

my $t = Testable.new: bot => ‘Releasable’;

$t.common-tests: help => “status | status link”;

$t.shortcut-tests: <release: release6:>,
                   <release release, release6 release6,>;

# The idea is to generate a pseudorealistic repo that
# is good enough for testing purposes.

my $mock = ‘t/data/rakudo’.IO;
rmtree $mock if $mock.e;
mkdir $mock;
run :cwd($mock), :out(Nil), ‘git’, ‘init’;
mkdir $mock.add: ‘docs’;
spurt $mock.add(‘docs/ChangeLog’), “New in 2090.07:\n + Additions:\n\n”;

my @releases = (
    ‘2090-08-19   Rakudo #990 (AlexDaniel)’,
    ‘2090-09-16   Rakudo #991’,
    ‘2090-10-21   Rakudo #992’,
    ‘2090-11-18   Rakudo #993’,
);

sub changelog(Block $do) {
    my $path = $mock.add: ‘docs/ChangeLog’;
    spurt $path, $do(slurp $path);
}

sub tag-last($tag-name, $new-section = “New in {$tag-name + 0.01}”  #← hahaha
                                     ~ “:\n + Additions:\n\n”     ) {
    my $sha = run(:cwd($mock), :out, ‘git’, ‘rev-parse’, ‘HEAD’)
              .out.slurp-rest.chomp;
    run :cwd($mock), ‘git’, ‘tag’, ‘--annotate’,
                     “--message=Blah $tag-name”, $tag-name;
    spurt $mock.add(‘VERSION’), $tag-name;
    changelog { $new-section ~ $_ } if defined $new-section
}

sub commit($message, :$log = True) {
    my $foo = ^9⁹ .pick;
    spurt $mock.add($foo), $foo;
    run :cwd($mock),            ‘git’, ‘add’, ‘--’, $foo;
    run :cwd($mock), :out(Nil), ‘git’, ‘commit’, “--message=$message”;

    my $release-guide = “=head2 Planned future releases\n\n… … …\n\n”
                       ~ @releases.map({ “  $_\n” }).join;
    spurt $mock.add(‘docs/release_guide.pod’), $release-guide;

    my $sha = run(:cwd($mock), :out, ‘git’, ‘rev-parse’, ‘HEAD’)
              .out.slurp-rest.chomp.substr: 0, 8;
    my $log-entry = $log ~~ Bool ?? “    + $message [$sha]\n” !! $log;
    changelog -> $file is copy {
        die without $file ~~ s/<after \n><before \n>/$log-entry/;
        $file
    } if $log;
    $sha
}

# TODO the number of blockers and the time left is not controllable

# Basics

commit ‘$!.pending (RT #68320)’;

my $link = ｢https://github.com/rakudo/rakudo/issues?q=is:issue+is:open+label:%22%E2%9A%A0+blocker+%E2%9A%A0%22｣;
$t.test(‘unknown format’,
        “{$t.bot-nick}: when?”,
        /^ <me($t)>‘, Next release in ’\d+‘ day’s?‘ and ≈’\d+‘ hour’s?‘. ’
           [ \d+‘ blocker’s? | ‘No blockers’ | “Blockers: $link” ]‘. ’
           ‘Unknown changelog format’ $/);
        #“{$t.our-nick}, Details: https://whatever.able/fakeupload”);


tag-last ‘2090.07’;
commit ‘.hyper and .race finally re-added’;
tag-last ‘2090.08’, Nil;
my $to-be-logged = commit ‘A change that should be logged’, :!log;

$t.test(‘not started yet’,
        “{$t.bot-nick}: status”,
        “{$t.our-nick}, Release date for Rakudo 2090.08 is listed in”
            ~ “ “Planned future releases”, but it was already released.”,
        /^ <me($t)>‘, Next release in ’\d+‘ day’s?‘ and ≈’\d+‘ hour’s?‘. ’
           [ \d+‘ blocker’s? | ‘No blockers’ | “Blockers: $link” ]‘. ’
           ‘Changelog for this release was not started yet’ $/,
        “{$t.our-nick}, Details: https://whatever.able/fakeupload”);

$t.test-gist(‘commits are listed even without a new section’,
             %(‘unreviewed.md’ => / $to-be-logged /) );

@releases.shift;

my $to-be-logged-not = commit ‘A change that should not be logged’, :!log;
my @real = ‘Furious whitespace changes’ xx 4;
@real.push: ‘Fix nothing’;
@real .= map: { commit $_, :!log };
my $log-entries = qq:to/END/;
New in 2090.09:
 + Deprecations:
    + Deprecate everything [de1e7ea1]
 + Fixes:
    + Fix nothing [@real[*-1]]
    + Furious whitespace changes [@real[0]] [@real[1]] [@real[2]]
        [@real[3]] [abcabcabcabc]
    + No really, this change is very important [@real[1]]

END
changelog { $log-entries ~ $_ };

run :cwd($mock), ‘git’, ‘add’, ‘--’, ‘docs/ChangeLog’;
commit “Changelog\n\nIntentionally not logged: $to-be-logged-not”, :!log;

$t.test(‘realistic output’,
        “{$t.bot-nick}: release”,
        “{$t.our-nick}, Release manager is not specified yet.”,
        /^ <me($t)>‘, Next release in ’\d+‘ day’s?‘ and ≈’\d+‘ hour’s?‘. ’
           [ \d+‘ blocker’s? | ‘No blockers’ | “Blockers: $link” ]‘. ’
           ‘6 out of 8 commits logged (⚠ 2 warnings)’ $/, # TODO ideally should be 7 out of 8
        “{$t.our-nick}, Details: https://whatever.able/fakeupload”);

$t.test-gist(‘gisted files look alright’,
             %(‘!warnings!’    =>
                 ‘de1e7ea1 was referenced but there is no commit with this id’
                 ~ “\n” ~ ‘abcabcabcabc should be 8 characters in length’,
               ‘unreviewed.md’ =>
                 /｢<pre>    + A change that should be logged｣
                  ｢ [<a href="https://github.com/rakudo/rakudo/commit/｣
                  $to-be-logged <.xdigit>+ ｢">｣ $to-be-logged ｢</a>]｣.*｢</pre>｣ # TODO .*
                 /,
              )
            );


$t.test(‘uncommitted changed from a link’,
        “{$t.bot-nick}: changelog https://gist.github.com/AlexDaniel/45b98a8bd5935a53a3ed4762ea5f5d43/raw/”,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        “{$t.our-nick}, 1 out of 8 commits logged”,
        “{$t.our-nick}, Details: https://whatever.able/fakeupload”);

# $t.last-test; # Deliberately no $t.last-test! (we can't repeat the first test)
$t.test(‘No uncaught messages’,
        “{$t.bot-nick}: help”,
        /^ <me($t)>‘, status | status link’ /);

done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

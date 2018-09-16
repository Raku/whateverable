#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Greppable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: password”;

$t.shortcut-tests: <grep: grep6:>,
                   <grep grep, grep6 grep6,>;

# Basics

$t.test(:30timeout, ‘basic query’,
        “{$t.bot-nick}: password”,
        /^ <me($t)>‘, ’(\d+)‘ lines, ’(\d+)‘ modules:’
           { cmp-ok +~$0, &[>], +~$1, ‘more lines than modules’ }
          ‘ https://whatever.able/fakeupload’ $/);


$t.test-gist(‘something was found’,
             %(‘result.md’ => /‘password’/));

$t.test-gist(‘is case insensitive’,
             %(‘result.md’ => /‘PASSWORD’/));

$t.test-gist(‘“…” is added to long paths’,
             %(‘result.md’ => /‘``…/01-basic.t``’/));

$t.test-gist(‘“…” is not added to root files’,
             %(‘result.md’ => none /‘``…/README.md``’/));

$t.test(‘single line/module returned’,
      “{$t.bot-nick}: ought to cover the same functionality as this class, maybe long-term we”,
      /^ <me($t)>‘, 1 line, 1 module: https://whatever.able/fakeupload’ $/);

$t.test(‘another query’,
        “{$t.bot-nick}: I have no idea”,
        /^ <me($t)>‘, ’\d+‘ lines, ’\d+‘ modules: https://whatever.able/fakeupload’ $/);

$t.test-gist(‘Proper format’, # assume that tadzik's modules don't change
             %(‘result.md’ =>
               /^^ ‘| [tadzik/File-Find<br>``…/01-file-find.t`` :*85*:]’
               ‘(https://github.com/tadzik/File-Find/blob/’
               <.xdigit>**40
               ‘/t/01-file-find.t#L85) | <code>exit 0; # <b>I have no idea</b>’
               ‘ what I'm doing, but I get Non-zero exit status w/o this</code> |’ $$/));

$t.test(:120timeout, ‘the output of git grep is split by \n, not something else’,
        “{$t.bot-nick}: foo”,
        /^ <me($t)>‘, ’\d+‘ lines, ’\d+‘ modules: https://whatever.able/fakeupload’ $/);

$t.test-gist(‘“\r” is actually in the output’,
             %(‘result.md’ => /“\r”/));


# treegrep

$t.test(‘treegrep finds nothing’,
        ‘treegrep: theoauneoahushoauesnhoaesuheoasheoa’,
        “{$t.our-nick}, Found nothing!”);

# Non-bot tests

my $timestamp = run :out, cwd => ‘data/all-modules’,
                    ‘git’, ‘show’, ‘-s’, ‘--format=%ct’, ‘HEAD’;

ok $timestamp, ‘Got the timestamp of HEAD in data/all-modules repo’;
my $age = now - $timestamp.out.slurp-rest;
cmp-ok $age, &[<], 24 × 60 × 60, ‘data/all-modules repo updated in 24h’;


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

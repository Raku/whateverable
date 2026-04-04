#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Bloatable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: d=compileunits 292dc6a,HEAD”;

$t.shortcut-tests: <bloat: bloat6: bloaty: bloaty6:>,
                   <bloat bloat, bloat6 bloat6, bloaty bloaty, bloaty6 bloaty6,
                    b b, b:>;

# Basics

$t.test(‘one commit’,
        “{$t.bot-nick}: HEAD”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘actual sha is mentioned’,
             %(‘result’ => /^ ‘HEAD(’<sha>‘)’ /));

$t.test-gist(‘something in the output’,
             %(‘result’ => / ‘TOTAL’ /));


$t.test(‘two commits’,
        “{$t.bot-nick}: 2017.01,HEAD”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘compares A and B’,
             %(‘result-00001’ => /^ ‘Comparing 2017.01 → HEAD(’<sha>‘)’ $$/));

$t.test-gist(‘something is shrinking’,
             %(‘result-00001’ => / ‘SHRINKING’ /));

$t.test-gist(‘something is growing’,
             %(‘result-00001’ => / ‘GROWING’ /));


$t.test(‘three commits’,
        “{$t.bot-nick}: 2017.01,2017.05,HEAD”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘compares A → B and B → C’,
             %(‘result-00001’ => /^ ‘Comparing 2017.01 → 2017.05’ $$/,
               ‘result-00002’ => /^ ‘Comparing 2017.05 → HEAD(’<sha>‘)’ $$/));


$t.test(‘older commits’,
        “{$t.bot-nick}: 2016.01,2017.01”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘the output is reasonably-sized and consistent’,
             %(‘result-00001’ => { .lines == 89 }));


$t.test(‘different source (using -d …)’,
        “{$t.bot-nick}: -d inputfiles 2016.01,2017.01”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘the output is indeed different for -d inputfile’,
             %(‘result-00001’ => { .lines == 9 }));

$t.test(‘different sources (using -d …)’,
        “{$t.bot-nick}: -d inputfiles,sections 2016.01,2017.01”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘the output is indeed different for -d inputfile,sections’,
             %(‘result-00001’ => { .lines == 87 }));


$t.test(‘different source (using d=…)’,
        “{$t.bot-nick}: d=inputfiles 2016.01,2017.01”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘the output is indeed different for dsinputfile’,
             %(‘result-00001’ => { .lines == 9 }));

$t.test(‘different sources (using d=…)’,
        “{$t.bot-nick}: d=inputfiles,sections 2016.01,2017.01”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘the output is indeed different for dsinputfile,sections’,
             %(‘result-00001’ => { .lines == 87 }));


$t.test(‘incorrect source (using -d …)’,
        “{$t.bot-nick}: -duhmm… 2017.01,HEAD”,
        /^ <me($t)>‘, No such data source: uhmm… (Did you mean one of these: ’ [\w+]+ % \s+ ‘ ?)’ $/);

$t.test(‘incorrect source (using d=…)’,
        “{$t.bot-nick}: d=uhmm… 2017.01,HEAD”,
        /^ <me($t)>‘, No such data source: uhmm… (Did you mean one of these: ’ [\w+]+ % \s+ ‘ ?)’ $/);


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

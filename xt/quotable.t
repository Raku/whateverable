#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Quotable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: /^ ‘bisect: ’ /”;

$t.shortcut-tests: <quote: quote6:>,
                   <quote quote, quote6 quote6,>;

# Basics
$t.test(‘basic test’,
        “{$t.bot-nick}: /^ ‘bisect: ’ /”,
        /^ <me($t)>‘, OK, working on it! This may take up to three minutes (’\d+‘ messages to process)’ $/,
        /^ <me($t)>‘, ’\d+‘ messages (2016-05-20⌁’\d\d\d\d‘-’\d\d‘-’\d\d‘): https://whatever.able/fakeupload’/,
        :150timeout);

$t.test-gist(‘lots of results’,
             %(‘result-#perl6.md’ => { 370 < .lines < 10_000 }));

$t.test-gist(‘all lines match our regex’,
             %(‘result-#perl6.md’ => { so .lines.all.starts-with(‘[` bisect:’) }));


$t.test(‘invalid regex’,
        “{$t.bot-nick}: ‘foo”,
        /^ <me($t)>‘, OK, working on it! This may take up to three minutes (’\d+‘ messages to process)’ $/,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘error message gisted’,
             %(‘result’ => /^ ‘===SORRY!=== Error while compiling’ /));


$t.test(‘one message only, please’,
        “{$t.bot-nick}: /^ ‘pre-GLR is, like, a different language...’ /”,
        /^ <me($t)>‘, OK, working on it! This may take up to three minutes (’\d+‘ messages to process)’ $/,
        “{$t.our-nick}, 1 message (2015-12-26): https://whatever.able/fakeupload”,
        :150timeout);

# Non-bot tests
subtest ‘all channels have recent data’, {
    my @tracked-channels = dir ‘data/irc’, test => { .starts-with(‘#’) && “data/irc/$_”.IO.d };
    ok @tracked-channels > 0, ‘at least one channel is tracked’;
    for @tracked-channels {
        dd $_;
        my $exists = “$_/{DateTime.now.earlier(:2days).Date}”.IO.e;
        todo ‘outdated data (issue #192)’, 3;
        ok $exists, “{.basename} is up-to-date (or was up-to-date 2 days ago)”;
        cmp-ok “$_.cache”.IO.modified.DateTime, &[>], DateTime.now.earlier(:2days),
               “$_ cache file was recently updated”;
        cmp-ok “$_.total”.IO.modified.DateTime, &[>], DateTime.now.earlier(:2days),
               “$_ cache file was recently updated”;
    }
}

$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

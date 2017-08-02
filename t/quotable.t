#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib ‘t/lib’;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Quotable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: /^ ‘bisect: ’ /”;

$t.shortcut-tests: <quote: quote, quote6: quote6,>,
                   <quote quote6>;

# Basics
$t.test(‘basic test’,
        “{$t.bot-nick}: /^ ‘bisect: ’ /”,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
       :150timeout);

$t.test-gist(‘lots of results’,
             %(‘result’ => { .lines > 390 }));

$t.test-gist(‘all lines match our regex’,
             %(‘result’ => { so .lines.all.starts-with(‘bisect:’) }));


$t.test(‘invalid regex’,
        “{$t.bot-nick}: ‘foo”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test-gist(‘lots of results’,
             %(‘result’ => /^ ‘===SORRY!=== Error while compiling’ /));
}

# Non-bot tests
todo ‘outdated data (issue #192)’, 2;
subtest ‘all channels have recent data’, {
    my @tracked-channels = dir ‘irc’, test => { .starts-with(‘#’) && “irc/$_”.IO.d };
    ok @tracked-channels > 0, ‘at least one channel is tracked’;
    for @tracked-channels {
        my $exists = “$_/{DateTime.now.earlier(:2days).Date}”.IO.e;
        ok $exists, “{.basename} is up-to-date (or was up-to-date 2 days ago)”;
    }
}

cmp-ok ‘irc/cache’.IO.modified.DateTime, &[>], DateTime.now.earlier(:2days),
       ‘cache file was recently updated’;


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

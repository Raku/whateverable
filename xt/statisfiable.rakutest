#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Statisfiable’;

$t.common-tests: help => “Available stats: core (CORE.setting size), install (size of the installation), libmoar (libmoar.so size)”;

$t.shortcut-tests: <stat: stat6: stats: stats6:>,
                   <stat stat, stat6 stat6, stats stats, stats6 stats6,>;

# Basics
$t.test(‘core (CORE.setting size)’,
        “{$t.bot-nick}: core”,
        “{$t.our-nick}, OK! Working on it…”,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
       :120timeout);

$t.test-gist(‘“core” result has some files’,
             %(‘plot.svg’ => True, ‘result’ => True));

$t.test(‘install (size of the installation)’,
        “{$t.bot-nick}: install”,
        “{$t.our-nick}, OK! Working on it…”,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
        :120timeout);

$t.test-gist(‘“install” result has some files’,
             %(‘plot.svg’ => True, ‘result’ => True));

$t.test(‘libmoar (libmoar.so size)’,
        “{$t.bot-nick}: libmoar”,
        “{$t.our-nick}, OK! Working on it…”,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
        :120timeout);

$t.test-gist(‘“libmoar” result has some files’,
             %(‘plot.svg’ => True, ‘result’ => True));


$t.test(‘invalid stats requested’,
        “{$t.bot-nick}: cakes-consumed”,
        /^ <me($t)>‘, I cannot recognize this command. See wiki for some examples: https://’ /);


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

#!/usr/bin/env perl6

BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;
use IRC::Client;

my $t = Huggable.new: bot => 'Huggable';

$t.common-tests: help => 'Like this: .hug <nick>';

#| .hug
#| .hug <nick>
$t.test('.hug',
        'hug',
        "hugs {$t.our-nick}");

$t.test('.hug <nick>',
        '.hug sibl',
        'hugs sibl');

$t.test('.hug <whatever actually>',
        '.hug everyone',
        'hugs everyone');

$t.test('<prefix> .hug <nick>',
        '<foobar> .hug ande',
        "hugs ande");

#| huggable6: hug
#| huggable6: hug <nick>
$t.test('huggable6: hug',
        "{$t.bot-nick}: hug",
        "hugs {$t.our-nick}"
       );
$t.test('huggable6: hug everyone',
        "{$t.bot-nick}: hug everyone",
        'hugs everyone'
       );

#| huggable6: <nick>...
$t.test('huggable6: sibl ande',
        "{$t.bot-nick}: sibl ande",
        'hugs sibl ande'
       );

$t.last-test;
done-testing;
END $t.end;

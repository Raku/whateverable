#!/usr/bin/env perl6

BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;
use IRC::Client;

my $t = Huggable.new: bot => ‘Huggable’;

$t.common-tests: help => ‘Like this: .hug’;

$t.test('.hug',
        'hug',
        "hugs");

$t.test('.hug <nick>',
        '.hug sibl',
        "hugs sibl");

$t.test('.hug <whatever actually>',
        '.hug everyone',
        "hugs everyone");

$t.test('<prefix> .hug <nick>',
        '<foobar> .hug ande',
        "hugs ande");

$t.last-test;
done-testing;
END $t.end;

#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Coverable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: f583f22 grep=SETTING:: say ‘hello’; say ‘world’”;

$t.shortcut-tests: <cover: cover6:>,
                   <cover cover, cover6 cover6, c c, c:>;

# Basics

$t.test(‘basic query on HEAD’,
        “{$t.bot-nick}: HEAD say ‘hi’”,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
        :50timeout);

$t.test-gist(‘basic gist test’, # let's assume say proto is not going to change
             %(‘result.md’ =>
               /^^ ｢| [src/core/io_operators.pm#L｣ (\d+) ｢](https://github.com/rakudo/rakudo/blob/｣
               <:hex>**40 ｢/src/core/io_operators.pm#L｣ $0 ｢) | ```proto sub say(\|) {*}``` |｣ $$/));

$t.test(‘using grep option’,
        “{$t.bot-nick}: 2017.06 grep=SETTING say ‘hi’”,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
        :50timeout);

$t.test-gist(‘stuff is filtered’,
             %(‘result.md’ => none / ‘/Perl6’ /));

$t.test-gist(‘the gist is not empty at all’,
             %(‘result.md’ => { .lines > 100}));

$t.test(‘refuse more than one commit’,
        “{$t.bot-nick}: HEAD, HEAD^ say ‘hi’”,
        “{$t.our-nick}, Coverable only works with one commit”);

$t.test(‘refuse a lot of commits’,
        “{$t.bot-nick}: releases say ‘hi’”,
        “{$t.our-nick}, Coverable only works with one commit”);


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

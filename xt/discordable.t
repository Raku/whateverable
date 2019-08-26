#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;

my $t = Testable.new: bot => ‘Evalable’, :discord;

is $t.our-nick, ‘testable’, ‘our-nick is testable...’;
is $t.^attributes.first(‘$!our-nick’).get_value($t), ‘discord6’, ‘... but we're faking discord6’;

$t.common-tests: help => “Like this: {$t.bot-nick}: say ‘hello’; say ‘world’”;

$t.shortcut-tests: <e: e6: eval: eval6:>,
                   <e e, e6 e6, eval eval, eval6 eval6, what:>;# what what,>;

# Basics

$t.test(‘basic “nick:” query’,
        “{$t.bot-nick}: say ‘hello’”,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «hello␤»’ $/);

$t.test(‘basic “nick,” query’,
        “{$t.bot-nick}, say ‘hello’”,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «hello␤»’ $/);

$t.test(‘“eval:” shortcut’,
        ‘eval: say ‘hello’’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «hello␤»’ $/);

$t.test(‘“eval6:” shortcut’,
        ‘eval6: say ‘hello’’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «hello␤»’ $/);

$t.test(‘“eval” shortcut does not work’,
        ‘eval say ‘hello’’);

$t.test(‘“eval6” shortcut does not work’,
        ‘eval6 HEAD say ‘hello’’);

$t.test(‘too long output is uploaded’,
        ‘eval: .say for ^1000’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «0␤1␤2␤3␤4’ <-[…]>+ ‘…»’ $/,
        “{$t.our-nick}, Full output: https://whatever.able/fakeupload”
       );

$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

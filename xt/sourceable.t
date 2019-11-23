#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;

my $t = Testable.new: bot => 'Sourceable';

$t.common-tests: help => "Like this: {$t.bot-nick}: Int, 'base'";

$t.test('call on type',
        "{$t.bot-nick}: Int, 'base'",
        /'https://github.com/rakudo/rakudo/blob/' .+? 'src/core/Int.pm6'/);

$t.test('call on object',
        "{$t.bot-nick}: 42.3, 'base'",
        /'https://github.com/rakudo/rakudo/blob/' .+? 'src/core/Rational.pm6'/);

$t.test('call with args',
        "{$t.bot-nick}: 42, 'base', \\(16)",
        /'https://github.com/rakudo/rakudo/blob/' .+? 'src/core/Int.pm6'/);

$t.last-test;
done-testing;
END $t.end;

#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;

my $t = Testable.new: bot => 'Sourceable';

$t.common-tests: help => “Like this: {$t.bot-nick}: 42.base(16)”;

$t.shortcut-tests: (‘s:’, ),
                   <s s,>;

my $link = ‘https://github.com/rakudo/rakudo/blob/’;

$t.test(‘code object’,
        “{$t.bot-nick}: &copy”,
        /$link .+? ‘src/core.c/io_operators.pm6’/);

$t.test(‘sub without ampersand’,
        “{$t.bot-nick}: copy”,
        /$link .+? ‘src/core.c/io_operators.pm6’/);

$t.test(‘sub with args (parens)’,
        “{$t.bot-nick}: ” ~ ｢sprintf('<%#B>', 12)｣,
        /$link .+? ‘src/core.c/Cool.pm6’/);

$t.test(‘sub with args no parens’,
        “{$t.bot-nick}: ” ~ ｢sprintf '<%#B>', 12｣,
        /$link .+? ‘src/core.c/Cool.pm6’/);

$t.test(‘method on type’,
        “{$t.bot-nick}: Int.base”,
        /$link .+? ‘src/core.c/Int.pm6’/);

$t.test(‘method on object’,
        “{$t.bot-nick}: 42.3.base”,
        /$link .+? ‘src/core.c/Rational.pm6’/);

$t.test(‘method with args (parens)’,
        “{$t.bot-nick}: 42.base(16)”,
        /$link .+? ‘src/core.c/Int.pm6’/);

$t.test(‘method with args: colon’,
        “{$t.bot-nick}: 42.base: 16”,
        /$link .+? ‘src/core.c/Int.pm6’/);

$t.test(‘operator’,
        “{$t.bot-nick}: ” ~ ｢&infix:['+<']｣,
        /$link .+? ‘src/core.c/Numeric.pm6’/);

$t.test(‘operator with args’,
        “{$t.bot-nick}: ” ~ ｢&infix:['+<'](1, 2)｣,
        /$link .+? ‘src/core.c/Int.pm6’/);

$t.test(‘infix operator’,
        “{$t.bot-nick}: 1 < 2”,
        /$link .+? ‘src/core.c/Int.pm6’/);


# Other revisions (not HEAD)

$t.test(‘running on a provided revision’,
        “{$t.bot-nick}: 6c2f24455c NaN.FatRat.Bool()”,
        /^ <me($t)>‘, https://github.com/rakudo/rakudo/blob/6c2f244/src/core/Rational.pm6#L77’ $/);


# Errors

$t.test(‘not a code-like thing’,
        “{$t.bot-nick}: ∞”,
        /^ <me($t)>‘, No idea, boss. Can you give me a Code object?’ $/);

$t.test(‘syntax error’,
        “{$t.bot-nick}: 2 +”,
        /^ <me($t)>‘, No idea, boss. Can you give me a Code object? Output: ’ .* ‘===’ .* ‘SORRY!’ .* $/);


# Proto vs actual method

my $proto-line;
$t.test(‘proto without parens’,
        “{$t.bot-nick}: 42.hash”,
        /$link .+? ‘src/core.c/Any.pm6#L’(\d+) {$proto-line=+~$0} $/);

my $concrete-line;
$t.test(‘concrete with parens’,
        “{$t.bot-nick}: 42.hash()”,
        /$link .+? ‘src/core.c/Any.pm6#L’(\d+) {$concrete-line=+~$0} $/);

cmp-ok $proto-line, &[<], $concrete-line, ‘proto line is before the actual method’;


# More complex cases

$t.test(‘range with infix dot’,
        “{$t.bot-nick}: ^10 .reverse.skip(10).iterator()”,
        /$link .+? ‘src/core.c/Seq.pm6’/);

$t.test(‘range with infix dot (no parens for method call)’,
        “{$t.bot-nick}: ^10 .reverse.skip(10).iterator”,
        /$link .+? ‘src/core.c/Seq.pm6’/);

$t.test(‘atomic op’,
        “{$t.bot-nick}: ” ~ ｢&postfix:<⚛++>(my atomicint $x)｣,
        /$link .+? ‘src/core.c/atomicops.pm6’/);

$t.test(‘skipping of undefined candidates’,
        “{$t.bot-nick}: ” ~ ｢/^/.ACCEPTS(any("opensuse", "linux"))｣,
        /$link .+? ‘src/core.c/Code.pm6’/);

$t.test(‘large piece of code’,
        “{$t.bot-nick}: ” ~ ｢Seq.new(class :: does Iterator { has $!n = 10; method pull-one {say "pulling!"; $!n-- and 42 or IterationEnd }; method skip-one { $!n-- }; method count-only { 10 } }.new).tail()｣,
        /$link .+? ‘src/core.c/Any-iterable-methods.pm’/);

$t.test(‘stderr warnings are ignored’,
        “{$t.bot-nick}: ” ~ ｢(my %b = :1a).ACCEPTS(my %a = :1a)｣,
        /$link .+? ‘src/core.c/Map.pm6’/);

$t.last-test;
done-testing;
END $t.end;

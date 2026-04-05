#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Nativecallable’;

$t.common-tests: help => “Like this {$t.bot-nick}: <some C definition>”;

$t.shortcut-tests: <nativecall: nativecall6:>,
                   <nativecall nativecall, nativecall6 nativecall6,>;

# Basics
$t.test(‘basic struct’,
        “{$t.bot-nick}: ” ~ ｢struct s {int b; char* c;};｣,
        “{$t.our-nick}, ”
            ~ ｢class s is repr('CStruct') is export {␉has int32 $.b; # int b␉has Str $.c; # char* c }｣);

$t.test(‘basic sub’,
        “{$t.bot-nick}: void foo(char *a);”,
        "{$t.our-nick}," ~ 'sub foo(Str $a # char*) is native(LIB)  is export { * }');

$t.test-gist(‘gisted results’,
             %(‘Result.pm6’ => /^ ‘## Enumerations … … … … … … … … …’ $/));

$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

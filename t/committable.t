#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use Test;
use lib ‘t/lib’;
use Testable;

my $t = Testable.new(bot => ‘./Committable.p6’);

# Help messages

$t.test(‘help message’,
        “{$t.bot-nick}, helP”,
        “{$t.our-nick}, Like this: {$t.bot-nick}: f583f22,HEAD say ‘hello’; say ‘world’”);

$t.test(‘help message’,
        “{$t.bot-nick},   HElp?  ”,
        “{$t.our-nick}, Like this: {$t.bot-nick}: f583f22,HEAD say ‘hello’; say ‘world’”);

$t.test(‘source link’,
        “{$t.bot-nick}: Source   ”,
        “{$t.our-nick}, https://github.com/perl6/whateverable”);

$t.test(‘source link’,
        “{$t.bot-nick}:   sourcE?  ”,
        “{$t.our-nick}, https://github.com/perl6/whateverable”);

$t.test(‘source link’,
        “{$t.bot-nick}:   URl ”,
        “{$t.our-nick}, https://github.com/perl6/whateverable”);

$t.test(‘source link’,
        “{$t.bot-nick}:  urL?   ”,
        “{$t.our-nick}, https://github.com/perl6/whateverable”);

# Basics

$t.test(‘basic “nick:” query’,
        “{$t.bot-nick}: HEAD say ‘hello’”,
        “{$t.our-nick}, ¦«HEAD»: hello”);

$t.test(‘basic “nick,” query’,
        “{$t.bot-nick}, HEAD say ‘hello’”,
        “{$t.our-nick}, ¦«HEAD»: hello”);

$t.test(‘“commit:” shortcut’,
        ‘commit: HEAD say ‘hello’’,
        “{$t.our-nick}, ¦«HEAD»: hello”);

$t.test(‘“commit,” shortcut’,
        ‘commit, HEAD say ‘hello’’,
        “{$t.our-nick}, ¦«HEAD»: hello”);

$t.test(‘“commit6:” shortcut’,
        ‘commit6: HEAD say ‘hello’’,
        “{$t.our-nick}, ¦«HEAD»: hello”);

$t.test(‘“commit6,” shortcut’,
        ‘commit6, HEAD say ‘hello’’,
        “{$t.our-nick}, ¦«HEAD»: hello”);

$t.test(‘“commit” shortcut does not work’,
        ‘commit HEAD say ‘hello’’);

$t.test(‘“commit6” shortcut does not work’,
        ‘commit6 HEAD say ‘hello’’);

$t.test(‘specific commit’,
        ‘commit: f583f22 say $*PERL.compiler.version’,
        “{$t.our-nick}, ¦«f583f22»: v2016.06.183.gf.583.f.22”);

$t.test(‘too long output is uploaded’,
        ‘commit: HEAD .say for ^1000’,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

# Exit code & exit signal

$t.test(‘exit code’,
        ‘commit: 2015.12 say ‘foo’; exit 42’,
        “{$t.our-nick}, ¦«2015.12»: foo «exit code = 42»”);

$t.test(‘exit signal’,
        ‘commit: 2016.03 say ^1000 .grep: -> $n {([+] ^$n .grep: -> $m {$m and $n %% $m}) == $n }’,
        “{$t.our-nick}, ¦«2016.03»:  «exit signal = SIGSEGV (11)»”);

# STDIN

$t.test(‘stdin’,
        ‘commit: HEAD say lines[0]’,
        “{$t.our-nick}, ¦«HEAD»: ♥🦋 ꒛㎲₊⼦🂴⧿⌟ⓜ≹℻ 😦⦀🌵 🖰㌲⎢➸ 🐍💔 🗭𐅹⮟⿁ ⡍㍷⽐”);

$t.test(‘set custom stdin’,
        ‘commit: stdIN custom string␤another line’,
        “{$t.our-nick}, STDIN is set to «custom string␤another line»”);

$t.test(‘test custom stdin’,
        ‘committable6: HEAD dd lines’,
        “{$t.our-nick}, ¦«HEAD»: ("custom string", "another line").Seq”);

$t.test(‘reset stdin’,
        ‘commit: stdIN rESet’,
        “{$t.our-nick}, STDIN is reset to the default value”);

$t.test(‘test stdin after reset’,
        ‘commit: HEAD say lines[0]’,
        “{$t.our-nick}, ¦«HEAD»: ♥🦋 ꒛㎲₊⼦🂴⧿⌟ⓜ≹℻ 😦⦀🌵 🖰㌲⎢➸ 🐍💔 🗭𐅹⮟⿁ ⡍㍷⽐”);

$t.test(‘stdin line count’,
        ‘commit: HEAD say +lines’,
        “{$t.our-nick}, ¦«HEAD»: 10”);

$t.test(‘stdin word count’,
        ‘commit: HEAD say +$*IN.words’,
        “{$t.our-nick}, ¦«HEAD»: 100”);

$t.test(‘stdin char count’,
        ‘commit: HEAD say +slurp.chars’,
        “{$t.our-nick}, ¦«HEAD»: 500”);

# Ranges and multiple commits

$t.test(‘“releases” query’,
        ‘commit: releases say $*PERL’,
        /^ <{$t.our-nick}> ‘, ¦«2015.10,2015.11»: Perl 6 (6.b)␤¦«2015.12,2016.02,2016.03,2016.04,2016.05,2016.06,2016.07.1,2016.08.1,’ <-[‘»’]>* ‘HEAD»: ’ .* $/);

$t.test(‘multiple commits separated by comma’,
        “commit: 2016.02,2016.03,9ccd848,HEAD say ‘hello’”,
        “{$t.our-nick}, ¦«2016.02,2016.03,9ccd848,HEAD»: hello”);

$t.test(‘commit~num syntax’,
        ‘commit: 2016.04~100,2016.04 say $*PERL.compiler.version’,
        “{$t.our-nick}, ¦«2016.04~100»: v2016.03.1.g.7.cc.37.b.3␤¦«2016.04»: v2016.04”);

$t.test(‘commit^^^ syntax’,
        ‘commit: 2016.03^^^,2016.03^^,2016.03^,2016.03 say 42’,
        “{$t.our-nick}, ¦«2016.03^^^,2016.03^^,2016.03^,2016.03»: 42”);

$t.test(‘commit..commit range syntax’,
        ‘commit: 2016.07~74..2016.07~72 say ‘a’ x 9999999999999999999’,
        /^ <{$t.our-nick}> ‘, ¦«8ea2ae8,586f784»: ␤¦«87e8067,b31be7b,17e2679,2cc0f06,7242188,5d57154,6524d45,45c205a,d4b71b7,7799dbf,7e45d6b,abe034b,f772323,cbf1171,b11477f»: repeat count (-8446744073709551617) cannot be negative␤  in block <unit> at /tmp/’ \w+ ‘ line 1␤ «exit code = 1»’ $/);

# Special characters

$t.test(‘special characters’,
        ‘commit: HEAD say (.chr for ^128).join’,
        $t.our-nick ~ ‘, ¦«HEAD»: ␀␁␂␃␄␅␆␇␈␉␤␋␌␍␎␏␐␑␒␓␔␕␖␗␘␙␚␛␜␝␞␟ !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~␡’);

$t.test(‘␤ works like an actual newline’,
        ‘commit: HEAD # This is a comment ␤ say ｢hello world!｣’,
        “{$t.our-nick}, ¦«HEAD»: hello world!”);

# URLs

$t.test(‘fetching code from urls’,
        ‘commit: HEAD https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL.”,
        “{$t.our-nick}, ¦«HEAD»: url test”);

$t.test(‘wrong url’,
        ‘commit: HEAD http://github.org/sntoheausnteoahuseoau’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (HTTP status line is 404 Not Found).”);

$t.test(‘wrong mime type’,
        ‘commit: HEAD https://www.wikipedia.org/’,
        “{$t.our-nick}, It looks like a URL, but mime type is ‘text/html’ while I was expecting something with ‘text/plain’ or ‘perl’ in it. I can only understand raw links, sorry.”);

# Extra tests

$t.test(‘last basic query, just in case’, # keep it last in this file
        “{$t.bot-nick}: HEAD say ‘hello’”,
        “{$t.our-nick}, ¦«HEAD»: hello”);

END {
    $t.end;
    sleep 1;
}

done-testing;

#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use IRC::Client;
use Testable;

my $t = Testable.new: bot => ‘Evalable’;

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

# Exit code & exit signal

$t.test(‘exit code’,
        ‘eval: say ‘foo’; exit 42’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(exit code 42) foo␤»’ $/);


$t.test(‘exit signal’,
        ‘eval: use NativeCall; sub strdup(int64) is native(Str) {*}; strdup(0)’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(signal SIGSEGV) »’ $/);

# STDIN

$t.test(‘stdin’,
        ‘eval: say lines[0]’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «♥🦋 ꒛㎲₊⼦🂴⧿⌟ⓜ≹℻ 😦⦀🌵 🖰㌲⎢➸ 🐍💔 🗭𐅹⮟⿁ ⡍㍷⽐␤»’ $/);

$t.test(‘set custom stdin’,
        ‘eval: stdIN custom string␤another line’,
        “{$t.our-nick}, STDIN is set to «custom string␤another line»”);

$t.test(‘test custom stdin’,
        ‘eval: dd lines’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «("custom string", "another line").Seq␤»’ $/);

$t.test(‘reset stdin’,
        ‘eval: stdIN rESet’,
        “{$t.our-nick}, STDIN is reset to the default value”);

$t.test(‘test stdin after reset’,
        ‘eval: say lines[0]’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «♥🦋 ꒛㎲₊⼦🂴⧿⌟ⓜ≹℻ 😦⦀🌵 🖰㌲⎢➸ 🐍💔 🗭𐅹⮟⿁ ⡍㍷⽐␤»’ $/);

$t.test(‘stdin line count’,
        ‘eval: say +lines’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «10␤»’ $/);

$t.test(‘stdin word count’,
        ‘eval: say +$*IN.words’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «100␤»’ $/);

$t.test(‘stdin char count’,
        ‘eval: say +slurp.chars’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «500␤»’ $/);

$t.test(‘stdin numbers’,
        ‘eval: say slurp().comb(/\d+/)’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(4𝟮)␤»’/);

$t.test(‘stdin words’,
        ‘eval: say slurp().comb(/\w+/)’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(hello world 4𝟮)␤»’/);

$t.test(‘stdin No’,
        ‘eval: say slurp().comb(/<:No>+/)’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(½)␤»’/);

$t.test(‘stdin Nl’,
        ‘eval: say slurp().comb(/<:Nl>+/)’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(Ⅵ)␤»’/);

$t.test(‘huge stdin is not replied back fully’,
        ‘eval: stdin https://raw.githubusercontent.com/perl6/mu/master/misc/camelia.txt’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        “{$t.our-nick}, STDIN is set to «Camelia␤␤The Camelia image is copyright 2009 by Larry Wall.  Permission to use␤is granted under the…»”);

# Special characters
#`{ What should we do with colors?
$t.test(‘special characters’,
        ‘eval: say (.chr for ^128).join’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «␀␁␂␃␄␅␆␇␈␉␤␋␌␍␎␏␐␑␒␓␔␕␖␗␘␙␚␛␜␝␞␟ !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~␡␤»’ $/);

$t.test(‘␤ works like an actual newline’,
        ‘eval: # This is a comment ␤ say ｢hello world!｣’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «hello world!␤»’ $/);
}

# URLs

$t.test(‘fetching code from urls’,
        ‘eval: https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «url test␤»’ $/);

$t.test(‘comment after a url’,
        ‘eval: https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6 # this is a comment’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «url test␤»’ $/);

$t.test(‘comment after a url (without #)’,
        ‘eval: https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6 ← like this!’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «url test␤»’ $/);

$t.test(‘wrong url’,
        ‘eval: http://github.com/sntoheausnteoahuseoau’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (HTTP status line is 404 Not Found)”);

$t.test(‘wrong mime type’,
        ‘eval: https://www.wikipedia.org/’,
        “{$t.our-nick}, It looks like a URL, but mime type is ‘text/html’ while I was expecting something with ‘text/plain’ or ‘perl’ in it. I can only understand raw links, sorry.”);

$t.test(‘malformed link (failed to resolve)’,
        ‘eval: https://perl6.or’,
        /^ <me($t)>‘, It looks like a URL, but for some reason I cannot download it (Failed to resolve host name 'perl6.or' with family ’\w+‘. Error: 'Name or service not known')’ $/);

$t.test(‘malformed link (could not parse)’,
        ‘eval: https://:P’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (Could not parse URI: https://:P)”);

# Camelia replacement

my @alts = <master rakudo r r-m m p6 perl6>;

for (‘’, ‘ ’) X~ (@alts X~ ‘: ’, ‘:’) {
    $t.test(“answers on ‘$_’ when camelia is not around”,
            $_ ~ “say ‘$_’”,
            /^ <me($t)>‘, rakudo-moar ’<sha>“: OUTPUT: «$_␤»” $/)
}

my $camelia = IRC::Client.new(:nick(‘camelia’)
                              :host<127.0.0.1> :port(%*ENV<TESTABLE_PORT>)
                              :channels<#whateverable_evalable6>);
start $camelia.run;
sleep 1;

for (‘’, ‘ ’) X~ (@alts X~ ‘: ’) {
    $t.test(“camelia is back, be silent (‘$_’)”,
            $_ ~ “say ‘$_’”)
}

for (‘’, ‘ ’) X~ (@alts X~ ‘:’) {
    $t.test(:30timeout, “but answers on ‘$_’ without a space”,
            $_ ~ “say ‘$_’”,
            /^ <me($t)>‘, rakudo-moar ’<sha>“: OUTPUT: «$_␤»” $/)
}

$camelia.quit;
sleep 1;

for (‘’, ‘ ’) X~ (@alts X~ ‘: ’, ‘:’) {
    $t.test(“answers on ‘$_’ when camelia is not around again”,
            $_ ~ “say ‘$_’”,
            /^ <me($t)>‘, rakudo-moar ’<sha>“: OUTPUT: «$_␤»” $/)
}

# Code autodetection

$t.test(‘‘m:’ is not even needed’,
        ‘say ‘42’’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «42␤»’ $/);

$t.test(‘autodetection is smart enough’,
        ‘say you actually start your message with “say”’);

$t.test(‘advanced autodetection’,
        ‘42 . note; my $x = 50’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «42␤»’ $/);

$t.test(‘invalid code is ignored’,
        ‘42 .note∞ my $x = 50’);

$t.test(‘invalid code is ignored’,
        ‘say calls .gist, right? so it's probably .gist calling .Str’);

$t.test(‘useless stuff is ignored’,
        ‘42’);

$t.test(‘whitespace-only stuff is ignored’,
        ‘    ’);

$t.test(‘empty output is ignored’,
        ‘my $x = 42’);

$t.test(‘timeouts are ignored’,
        ‘sleep ∞’);

$t.test(‘s/…/…/ is ignored’,
        ‘s/each block/each comp unit/;’);

$t.test(‘segfaults are not ignored’,
        ‘use NativeCall; sub strdup(int64) is native(Str) {*}; strdup(0)’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(signal SIGSEGV) »’ $/);

# Timeouts

$t.test(‘timeout’,
        ‘eval: say ‘Zzzz…’; sleep ∞’,
        /^ <me($t)>‘, rakudo-moar ’<sha>‘: OUTPUT: «(signal SIGHUP) Zzzz…␤«timed out after 10 seconds»»’ $/);


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

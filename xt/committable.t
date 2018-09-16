#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;

my $t = Testable.new: bot => ‘Committable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: f583f22,HEAD say ‘hello’; say ‘world’”;

$t.shortcut-tests: <c: c6: commit: commit6:
                   mc: ec: mch: ech: ma: all: 6c: v6c: v6.c: 6.c:
                   releases:>,
                   <c c, c6 c6, commit commit, commit6 commit6, what:
                   mc  ec  mch  ech  ma  all  what  6c  v6c  v6.c  6.c
                   mc, ec, mch, ech, ma, all, what, 6c, v6c, v6.c, 6.c,
                   releases releases,>;

$t.test(‘fallback’,
        “{$t.bot-nick}: wazzup?”,
        “{$t.our-nick}, I cannot recognize this command. See wiki for some examples: https://github.com/perl6/whateverable/wiki/Committable”);

# Basics

$t.test(‘basic “nick:” query’,
        “{$t.bot-nick}: HEAD say ‘hello’”,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «hello␤»’ $/);

$t.test(‘basic “nick,” query’,
        “{$t.bot-nick}, HEAD say ‘hello’”,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «hello␤»’ $/);

$t.test(‘“commit:” shortcut’,
        ‘commit: HEAD say ‘hello’’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «hello␤»’ $/);

$t.test(‘“commit6:” shortcut’,
        ‘commit6: HEAD say ‘hello’’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «hello␤»’ $/);

$t.test(‘“commit” shortcut does not work’,
        ‘commit HEAD say ‘hello’’);

$t.test(‘“commit6” shortcut does not work’,
        ‘commit6 HEAD say ‘hello’’);

$t.test(｢“c:\” is a path and therefore does not work｣,
        ｢c:\HEAD say ‘hello’｣);

$t.test(｢“c:/” is a path and therefore does not work｣,
        ｢c:/HEAD say ‘hello’｣);

$t.test(‘specific commit’,
        ‘commit: f583f22 say $*PERL.compiler.version’,
        “{$t.our-nick}, ¦f583f22: «v2016.06.183.gf.583.f.22␤»”);

$t.test(‘too long output is uploaded’,
        ‘commit: HEAD .say for ^1000’,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

# Exit code & exit signal

$t.test(‘exit code’,
        ‘commit: 2015.12 say ‘foo’; exit 42’,
        “{$t.our-nick}, ¦2015.12: «foo␤ «exit code = 42»»”);

$t.test(‘exit signal’,
        ‘commit: 2016.03 say ^1000 .grep: -> $n {([+] ^$n .grep: -> $m {$m and $n %% $m}) == $n }’,
        “{$t.our-nick}, ¦2016.03: « «exit signal = SIGSEGV (11)»»”);

# STDIN

$t.test(‘stdin’,
        ‘commit: HEAD say lines[0]’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «♥🦋 ꒛㎲₊⼦🂴⧿⌟ⓜ≹℻ 😦⦀🌵 🖰㌲⎢➸ 🐍💔 🗭𐅹⮟⿁ ⡍㍷⽐␤»’ $/);

$t.test(‘set custom stdin’,
        ‘commit: stdIN custom string␤another line’,
        “{$t.our-nick}, STDIN is set to «custom string␤another line»”);

$t.test(‘test custom stdin’,
        ‘committable6: HEAD dd lines’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «("custom string", "another line").Seq␤»’ $/);

$t.test(‘reset stdin’,
        ‘commit: stdIN rESet’,
        “{$t.our-nick}, STDIN is reset to the default value”);

$t.test(‘test stdin after reset’,
        ‘commit: HEAD say lines[0]’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «♥🦋 ꒛㎲₊⼦🂴⧿⌟ⓜ≹℻ 😦⦀🌵 🖰㌲⎢➸ 🐍💔 🗭𐅹⮟⿁ ⡍㍷⽐␤»’ $/);

$t.test(‘stdin line count’,
        ‘commit: HEAD say +lines’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «10␤»’ $/);

$t.test(‘stdin word count’,
        ‘commit: HEAD say +$*IN.words’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «100␤»’ $/);

$t.test(‘stdin char count’,
        ‘commit: HEAD say +slurp.chars’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «500␤»’ $/);

$t.test(‘stdin numbers’,
        ‘commit: HEAD say slurp().comb(/\d+/)’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «(4𝟮)␤»’/);

$t.test(‘stdin words’,
        ‘commit: HEAD say slurp().comb(/\w+/)’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «(hello world 4𝟮)␤»’/);

$t.test(‘stdin No’,
        ‘commit: HEAD say slurp().comb(/<:No>+/)’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «(½)␤»’/);

$t.test(‘stdin Nl’,
        ‘commit: HEAD say slurp().comb(/<:Nl>+/)’,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «(Ⅵ)␤»’/);

$t.test(‘huge stdin is not replied back fully’,
        ‘commit: stdin https://raw.githubusercontent.com/perl6/mu/master/misc/camelia.txt’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        “{$t.our-nick}, STDIN is set to «Camelia␤␤The Camelia image is copyright 2009 by Larry Wall.  Permission to use␤is granted under the…»”);

# Ranges and multiple commits

$t.test(‘“releases” query’,
        ‘commit: releases say $*PERL’,
        /^ $($t.our-nick) ‘, ¦releases (’\d+‘ commits): «Perl 6 (6.c)␤»’ $/,
        :20timeout);

$t.test(‘“v6c” query’,
        ‘commit: v6c say $*PERL’,
        /^ $($t.our-nick) ‘, ¦v6c (’\d+‘ commits): «Perl 6 (6.c)␤»’ $/,
        :20timeout);

$t.test(‘“6.c” query’,
        ‘commit: 6.c say $*PERL’,
        /^ $($t.our-nick) ‘, ¦6.c (’\d+‘ commits): «Perl 6 (6.c)␤»’ $/,
        :20timeout);

$t.test(‘“6c” query’,
        ‘commit: 6c say $*PERL’,
        /^ $($t.our-nick) ‘, ¦6c (’\d+‘ commits): «Perl 6 (6.c)␤»’ $/,
        :20timeout);

$t.test(‘“6c,” does not work’,
        ‘6c, say ‘6c, is actually working…’’);

$t.test(‘“all” query (same output everywhere)’,
        ‘commit: all say 'hi'’, # ASCII quotes because they are supported everywhere
        /^ $($t.our-nick) ‘, ¦all (’\d+‘ commits): «hi␤»’ $/,
        :30timeout);

$t.test(‘“all” query (different output everywhere)’,
        ‘commit: all say rand’,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
        :30timeout);

$t.test(‘multiple commits separated by comma’,
        “commit: 2016.02,2016.03,9ccd848,HEAD say ‘hello’”,
        /^ <me($t)>‘, ¦2016.02,2016.03,9ccd848,HEAD(’<sha>‘): «hello␤»’ $/);

$t.test(‘commit~num syntax’,
        ‘commit: 2016.04~100,2016.04 say $*PERL.compiler.version’,
        “{$t.our-nick}, ¦2016.04~100: «v2016.03.1.g.7.cc.37.b.3␤» ¦2016.04: «v2016.04␤»”);

$t.test(‘commit^^^ syntax’,
        ‘commit: 2016.03^^^,2016.03^^,2016.03^,2016.03 say 42’,
        “{$t.our-nick}, ¦2016.03^^^,2016.03^^,2016.03^,2016.03: «42␤»”);

$t.test(‘commit..commit range syntax’,
        ‘commit: 2016.07~73..2016.07~72 say ‘a’ x 9999999999999999999’,
        /^ $($t.our-nick) ‘, ¦586f784,8ea2ae8: «␤» ¦87e8067: «repeat count (-8446744073709551617) cannot be negative␤  in block <unit> at /tmp/’ \w+ ‘ line 1␤␤ «exit code = 1»»’ $/);

$t.test(‘very old tags’,
        ‘commit: 2014.01,2014.02,2014.03 say 42’,
        “{$t.our-nick}, ¦2014.01,2014.02,2014.03: «42␤»”);

# Special characters
#`{ What should we do with colors?
$t.test(‘special characters’,
        ‘commit: HEAD say (.chr for ^128).join’,
        $t.our-nick ~ ‘, ¦HEAD(’<sha>‘): «␀␁␂␃␄␅␆␇␈␉␤␋␌␍␎␏␐␑␒␓␔␕␖␗␘␙␚␛␜␝␞␟ !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~␡␤»’);

$t.test(‘␤ works like an actual newline’,
        ‘commit: HEAD # This is a comment ␤ say ｢hello world!｣’,
        “{$t.our-nick}, ¦HEAD(’<sha>‘): «hello world!␤»”);
}

# URLs

$t.test(‘fetching code from urls’,
        ‘commit: HEAD https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «url test␤»’ $/);

$t.test(‘comment after a url’,
        ‘commit: HEAD https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6 # this is a comment’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «url test␤»’ $/);

$t.test(‘comment after a url (without #)’,
        ‘commit: HEAD https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6 ← like this!’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, ¦HEAD(’<sha>‘): «url test␤»’ $/);

$t.test(‘wrong url’,
        ‘commit: HEAD http://github.com/sntoheausnteoahuseoau’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (HTTP status line is 404 Not Found)”);

$t.test(‘wrong mime type’,
        ‘commit: HEAD https://www.wikipedia.org/’,
        “{$t.our-nick}, It looks like a URL, but mime type is ‘text/html’ while I was expecting something with ‘text/plain’ or ‘perl’ in it. I can only understand raw links, sorry.”);

$t.test(‘malformed link (failed to resolve)’,
        ‘commit: HEAD https://perl6.or’,
        /^ <me($t)>‘, It looks like a URL, but for some reason I cannot download it (Failed to resolve host name 'perl6.or' with family ’\w+‘. Error: 'Name or service not known')’ $/);

$t.test(‘malformed link (could not parse)’,
        ‘commit: HEAD https://:P’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (Could not parse URI: https://:P)”);

# Did you mean … ?

$t.test(‘Did you mean “all”?’,
        ‘commit: balls say 42’,
        “{$t.our-nick}, ¦balls: «Cannot find this revision (did you mean “all”?)»”);
$t.test(‘Did you mean “HEAD”?’,
        ‘commit: DEAD say 42’,
        “{$t.our-nick}, ¦DEAD: «Cannot find this revision (did you mean “HEAD”?)»”);
$t.test(‘Did you mean some release?’,
        ‘commit: 2016.55 say 42’,
        “{$t.our-nick}, ¦2016.55: «Cannot find this revision (did you mean “2016.05”?)»”);
$t.test(‘Did you mean some commit?’,
        ‘commit: d2c5694e50 say 42’,
        “{$t.our-nick}, ¦d2c5694: «Cannot find this revision (did you mean “d2c5684”?)»”);
$t.test(‘Only one commit is wrong (did you mean … ?)’,
        ‘commit: 2015.13,2015.12^ say 42’,
        “{$t.our-nick}, ¦2015.13: «Cannot find this revision (did you mean “2015.12”?)» ¦2015.12^: «42␤»”);
$t.test(‘Both commits are wrong (did you mean … ?)’,
        ‘commit: 2015.12^,2015.13,69fecb52eb2 say 42’,
        “{$t.our-nick}, ¦2015.12^: «42␤» ¦2015.13: «Cannot find this revision (did you mean “2015.12”?)» ¦69fecb5: «Cannot find this revision (did you mean “c9ebfc2”?)»”);

$t.test(‘Did you forget to specify a revision?’,
        ‘commit: say ‘hello world’’,
        “{$t.our-nick}, Seems like you forgot to specify a revision (will use “v6.c” instead of “say”)”,
        /^ $($t.our-nick) ‘, ¦v6.c (’\d+‘ commits): «hello world␤»’ $/,
        :20timeout);

# Gists

$t.test(‘nicely formatted gist’,
        ‘commit: 2016.05,2016.06,2016.07,2016.08,2016.09,2016.10,2016.11,2016.12,2017.01,2017.02,2017.03,2018.01’
            ~ ‘ say(‘this is a test’)xx⑳ if $*PERL.compiler.version < v2018’,
        “{$t.our-nick}, https://whatever.able/fakeupload”,
        :30timeout);

$t.test-gist(‘wrapped lines on long commit lists’,
             %(‘result’ => /^‘¦«2016.05,2016.06,2016.07,2016.08,2016.09,2016.10,2016.11,2016.12,2017.01,’
                            \n‘  2017.02,2017.03»:’\n‘this is a test’/));

# Timeouts

$t.test(:22timeout, ‘timeout’,
        ‘commit: 2015.12,HEAD say ‘Zzzz…’; sleep ∞’,
        /^ <me($t)>‘, ¦2015.12,HEAD(’<sha>‘): «Zzzz…␤«timed out after 10 seconds» «exit signal = SIGHUP (1)»»’ $/);

$t.test(‘committable does not crash’, # Issue #65
        ‘commit: 2015.07 say 1.0000001 ** (10 ** 8)’,
        “{$t.our-nick}, ¦2015.07: ««timed out after 10 seconds» «exit signal = SIGHUP (1)»»”);

# TODO test total timeout


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

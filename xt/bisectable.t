#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;

my $t = Testable.new: bot => ‘Bisectable’;

$t.common-tests: help => “Like this: bisectable6: old=2015.12 new=HEAD exit 1 if (^∞).grep(\{ last })[5] // 0 == 4”;

$t.shortcut-tests: <b: b6: bisect: bisect6:>,
                   <b b, b6 b6, bisect bisect, bisect6 bisect6, what: what what,>;

# Basics

$t.test(:50timeout, ‘bisect by exit code’,
        ‘bisect: exit 1 unless $*VM.version.Str.starts-with(‘2015’)’,
        /^ <me($t)>‘, Bisecting by exit code (old=2015.12 new=’<sha>‘). Old exit code: 0’ $/,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-02-04) https://github.com/rakudo/rakudo/commit/241e6c06a9ec4c918effffc30258f2658aad7b79”);

$t.test(:50timeout, ‘inverted exit code’,
        ‘bisect: exit 1 if     $*VM.version.Str.starts-with(‘2015’)’,
        /^ <me($t)>‘, Bisecting by exit code (old=2015.12 new=’<sha>‘). Old exit code: 1’ $/,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-02-04) https://github.com/rakudo/rakudo/commit/241e6c06a9ec4c918effffc30258f2658aad7b79”);

$t.test(:50timeout, ‘bisect by output’,
        ‘bisect: say $*VM.version.Str.split(‘.’).first # same but without proper exit codes’,
        /^ <me($t)>‘, Bisecting by output (old=2015.12 new=’<sha>‘) because on both starting points the exit code is 0’ $/,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-02-04) https://github.com/rakudo/rakudo/commit/241e6c06a9ec4c918effffc30258f2658aad7b79”);

$t.test(:50timeout, ‘bisect by exit signal’,
        ‘bisect: old=2015.10 new=2015.12 Buf.new(0xFE).decode(‘utf8-c8’) # RT 126756’,
        “{$t.our-nick}, Bisecting by exit signal (old=2015.10 new=2015.12). Old exit signal: 0 (None)”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2015-11-09) https://github.com/rakudo/rakudo/commit/3fddcb57f66a44d1a8adb7ecee1a3b403ab9f5d8”);

$t.test(:50timeout, ‘inverted exit signal’,
        ‘bisect: Buf.new(0xFE).decode(‘utf8-c8’) # RT 126756’,
        /^ <me($t)>‘, Bisecting by exit signal (old=2015.12 new=’<sha>‘). Old exit signal: 11 (SIGSEGV)’ $/,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-04-01) https://github.com/rakudo/rakudo/commit/a87fb43b6c85a496ef0358197625b5b417a0d372”);

$t.test(:50timeout, ‘nothing to bisect’,
        ‘bisect: say ‘hello world’; exit 42’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 42 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «hello world␤»”);

$t.test(:50timeout, ‘nothing to bisect, segmentation fault everywhere’,
        ‘bisect: old=2016.02 new=2016.03 Buf.new(0xFE).decode(‘utf8-c8’)’,
        “{$t.our-nick}, On both starting points (old=2016.02 new=2016.03) the exit code is 0, exit signal is 11 (SIGSEGV) and the output is identical as well”,
        “{$t.our-nick}, Output on both points: «»”);

$t.test(‘large output is uploaded’,
        ‘bisect: .say for ^1000; exit 5’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 5 and the output is identical as well’ $/,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test(‘exit code on old revision is 125’,
        ‘bisect: exit 125 if $*VM.gist eq ‘moar (2015.12)’’,
        “{$t.our-nick}, Exit code on “old” revision is 125, which means skip this commit. Please try another old revision”);

$t.test(‘exit code on new revision is 125’,
        ‘bisect: exit 125 unless $*VM.gist eq ‘moar (2015.12)’’,
        “{$t.our-nick}, Exit code on “new” revision is 125, which means skip this commit. Please try another new revision”);

# Custom starting points

$t.test(:50timeout, ‘custom starting points’,
        ‘bisect: old=2016.02 new 2016.03       say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, Bisecting by output (old=2016.02 new=2016.03) because on both starting points the exit code is 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120cab6d0bf55a3c96fd3bd9c2e841e7eb99b0”);

$t.test(:50timeout, ‘custom starting points using “bad” and “good” terms’,
        ‘bisect: good 2016.02 bad=2016.03      say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, Bisecting by output (old=2016.02 new=2016.03) because on both starting points the exit code is 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120cab6d0bf55a3c96fd3bd9c2e841e7eb99b0”);

$t.test(:50timeout, ‘swapped old and new revisions’,
        ‘bisect: old 2016.03 new 2016.02       say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, bisect init failure. See the log for more details”);

$t.test(:50timeout, ‘mixed case “old”/“new”’,
        ‘bisect: oLD 2016.02 NeW = 2016.03     say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, Bisecting by output (old=2016.02 new=2016.03) because on both starting points the exit code is 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120cab6d0bf55a3c96fd3bd9c2e841e7eb99b0”);

$t.test(:50timeout, ‘comma to separate old=/new=’,
        ‘bisect: old 2016.02, new= 2016.03     say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, Bisecting by output (old=2016.02 new=2016.03) because on both starting points the exit code is 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120cab6d0bf55a3c96fd3bd9c2e841e7eb99b0”);

$t.test(:50timeout, ‘mixed term styles’,
        ‘bisect: old =2016.02  ,  bad= 2016.03 say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, Bisecting by output (old=2016.02 new=2016.03) because on both starting points the exit code is 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120cab6d0bf55a3c96fd3bd9c2e841e7eb99b0”);

$t.test(:50timeout, ‘mixed term styles’,
        ‘bisect: good   2016.02,new  2016.03   say (^∞).grep({ last })[5]’,
        “{$t.our-nick}, Bisecting by output (old=2016.02 new=2016.03) because on both starting points the exit code is 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120cab6d0bf55a3c96fd3bd9c2e841e7eb99b0”);

# DWIM

$t.test(‘forgot the right syntax (comma)’,
        ‘bisect: 2016.02,2016.03 say 42’,
        “{$t.our-nick}, Using old=2016.02 new=2016.03 in an attempt to DWIM”,
        “{$t.our-nick}, On both starting points (old=2016.02 new=2016.03) the exit code is 0 and the output is identical as well”,
        “{$t.our-nick}, Output on both points: «42␤»”);

$t.test(‘forgot the right syntax (space)’,
        ‘bisect: 2016.02   2016.03 say 42’,
        “{$t.our-nick}, Using old=2016.02 new=2016.03 in an attempt to DWIM”,
        “{$t.our-nick}, On both starting points (old=2016.02 new=2016.03) the exit code is 0 and the output is identical as well”,
        “{$t.our-nick}, Output on both points: «42␤»”);

$t.test(‘forgot the right syntax (comma+space)’,
        ‘bisect: 2016.02  ,  2016.03 say 42’,
        “{$t.our-nick}, Using old=2016.02 new=2016.03 in an attempt to DWIM”,
        “{$t.our-nick}, On both starting points (old=2016.02 new=2016.03) the exit code is 0 and the output is identical as well”,
        “{$t.our-nick}, Output on both points: «42␤»”);

$t.test(‘forgot the right syntax (one revision only)’,
        ‘bisect: 2016.02 say 42’,
        “{$t.our-nick}, Using old=2016.02 new=HEAD in an attempt to DWIM”,
        /^ <me($t)>‘, On both starting points (old=2016.02 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «42␤»”);

$t.test(‘did not forget the right syntax (one suspicious)’,
        ‘bisect: old=2014.01,new=2014.02 2014.03 say 42’,
        “{$t.our-nick}, On both starting points (old=2014.01 new=2014.02) the exit code is 1 and the output is identical as well”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test(‘did not forget the right syntax (two suspicious)’,
        ‘bisect: old=2014.01,new=2014.02 2014.03,2014.04 say 42’,
        “{$t.our-nick}, On both starting points (old=2014.01 new=2014.02) the exit code is 1 and the output is identical as well”,
        “{$t.our-nick}, https://whatever.able/fakeupload”);

$t.test(‘non-revisions are ignored (one revision)’,
        ‘bisect: 2015.13 .say # heh’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «2015.13␤»”);

$t.test(‘non-revisions are ignored (two revisions)’,
        ‘bisect: 2016.12,2016.13 … BEGIN { say 42; exit 0 }’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «42␤»”);

$t.test(‘some non-revisions are ignored (one is correct)’,
        ‘bisect: 2016.05 2017.13 .say # heh’,
        “{$t.our-nick}, Using old=2016.05 new=HEAD in an attempt to DWIM”,
        /^ <me($t)>‘, On both starting points (old=2016.05 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «2017.13␤»”);

# Special characters
#`{ What should we do with colors?
$t.test(‘special characters’,
        ‘bisect: say (.chr for ^128).join’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: ” ~ ‘«␀␁␂␃␄␅␆␇␈␉␤␋␌␍␎␏␐␑␒␓␔␕␖␗␘␙␚␛␜␝␞␟ !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~␡␤»’);
}

$t.test(‘␤ works like an actual newline’,
        ‘bisect: # newline test ␤ say ‘hello world’; exit 42’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 42 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «hello world␤»”);

# URLs

$t.test(‘fetching code from urls’,
        ‘bisect: https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «url test␤»”);

$t.test(‘comment after a url’,
        ‘bisect: https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6 # this is a comment’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «url test␤»”);

$t.test(‘comment after a url (without #)’,
        ‘bisect: https://gist.githubusercontent.com/AlexDaniel/147bfa34b5a1b7d1ebc50ddc32f95f86/raw/9e90da9f0d95ae8c1c3bae24313fb10a7b766595/test.p6 ← like this!’,
        “{$t.our-nick}, Successfully fetched the code from the provided URL”,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «url test␤»”);

$t.test(‘wrong url’,
        ‘bisect: http://github.com/sntoheausnteoahuseoau’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (HTTP status line is 404 Not Found)”);

$t.test(‘wrong mime type’,
        ‘bisect: https://www.wikipedia.org/’,
        “{$t.our-nick}, It looks like a URL, but mime type is ‘text/html’ while I was expecting something with ‘text/plain’ or ‘perl’ in it. I can only understand raw links, sorry.”);

$t.test(‘malformed link (failed to resolve)’,
        ‘bisect: https://perl6.or’,
        /^ <me($t)>‘, It looks like a URL, but for some reason I cannot download it (Failed to resolve host name 'perl6.or' with family ’\w+‘. Error: 'Name or service not known')’ $/);

$t.test(‘malformed link (could not parse)’,
        ‘bisect: https://:P’,
        “{$t.our-nick}, It looks like a URL, but for some reason I cannot download it (Could not parse URI: https://:P)”);

# Did you mean … ?
$t.test(‘Did you mean “HEAD” (new)?’,
        ‘bisect: new=DEAD say 42’,
        “{$t.our-nick}, Cannot find revision “DEAD” (did you mean “HEAD”?)”);
$t.test(‘Did you mean “HEAD” (old)?’,
        ‘bisect: old=DEAD say 42’,
        “{$t.our-nick}, Cannot find revision “DEAD” (did you mean “HEAD”?)”);
$t.test(‘Did you mean some tag? (new)’,
        ‘bisect: new=2015.21 say 42’,
        “{$t.our-nick}, Cannot find revision “2015.21” (did you mean “2015.12”?)”);
$t.test(‘Did you mean some tag? (old)’,
        ‘bisect: old=2015.21 say 42’,
        “{$t.our-nick}, Cannot find revision “2015.21” (did you mean “2015.12”?)”);
$t.test(‘Did you mean some commit? (new)’,
        ‘bisect: new=a7L479b49dbd1 say 42’,
        “{$t.our-nick}, Cannot find revision “a7L479b49dbd1” (did you mean “a71479b”?)”);
$t.test(‘Did you mean some commit? (old)’,
        ‘bisect: old=a7L479b49dbd1 say 42’,
        “{$t.our-nick}, Cannot find revision “a7L479b49dbd1” (did you mean “a71479b”?)”);

$t.test(:50timeout, ‘Result is different on every revision’,
        ‘bisect: say rand’,
        /^ <me($t)>‘, Bisecting by output (old=2015.12 new=’<sha>‘) because on both starting points the exit code is 0’ $/,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2015-12-25) https://github.com/rakudo/rakudo/commit/07fecb52eb1fd07397659f19a5cf36dc61f84053”,
        “{$t.our-nick}, The result looks a bit unrealistic. Most probably the output is different on every commit (e.g. ｢bisect: say rand｣)”);

# Timeouts

$t.test(:21timeout, ‘timeout’,
        ‘bisect: say ‘Zzzz…’; sleep ∞’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0, exit signal is 1 (SIGHUP) and the output is identical as well’ $/,
        “{$t.our-nick}, Output on both points: «Zzzz…␤«timed out after 10 seconds»»”);

# TODO test timeouts during bisection

# Extra tests

# https://github.com/perl6/whateverable/issues/90
$t.test(‘working directory unchanged’,
        ‘bisect: for dir(‘lib’) { say ‘X’ }’,
        /^ <me($t)>‘, On both starting points (old=2015.12 new=’<sha>‘) the exit code is 0 and the output is identical as well’ $/,
        /^ <me($t)>‘, Output on both points: «’ ‘X␤’+ ‘»’ $/);


$t.test(:50timeout, ‘another working query #1’,
        ‘bisect: new=d3acb938 try { NaN.Rat == NaN; exit 0 }; exit 1’,
        “{$t.our-nick}, Bisecting by exit code (old=2015.12 new=d3acb93). Old exit code: 0”,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-05-02) https://github.com/rakudo/rakudo/commit/e2f1fa735132b9f43e7aa9390b42f42a17ea815f”);

$t.test(:50timeout, ‘another working query #2’,
        ‘bisect: for ‘q b c d’.words -> $a, $b { }; CATCH { exit 0 }; exit 1’,
        /^ <me($t)>‘, Bisecting by exit code (old=2015.12 new=’<sha>‘). Old exit code: 0’ $/,
        “{$t.our-nick}, bisect log: https://whatever.able/fakeupload”,
        “{$t.our-nick}, (2016-03-01) https://github.com/rakudo/rakudo/commit/1b6c901c10a0f9f65ac2d2cb8e7a362915fadc61”);

$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

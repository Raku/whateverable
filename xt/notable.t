#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;

my $t = Testable.new: bot => ‘Notable’;

$t.common-tests: help => “Like this: {$t.bot-nick}: weekly rakudo is now 10x faster”;

$t.shortcut-tests: <note: note6: weekly:>,
                   <note weekly>;

$t.test(‘fallback’,
        “{$t.bot-nick}: wazzup?”,
        “{$t.our-nick}, I cannot recognize this command. See wiki for some examples: https://github.com/perl6/whateverable/wiki/Notable”);

# No notes

my regex date { \d\d\d\d\-\d\d\-\d\dT\d\d\:\d\d\:\d\dZ }

$t.test(‘no notes’,
        “{$t.bot-nick}: blah”,
        “{$t.our-nick}, No notes for “blah””);

$t.test(‘no notes (shortcut)’,
        “weekly:”,
        “{$t.our-nick}, No notes for “weekly””);

$t.test(‘no notes, clearing’,
        “{$t.bot-nick}: clear blah”,
        “{$t.our-nick}, No notes for “blah””);

$t.test(‘no notes, clearing (shortcut)’,
        “weekly: clear”,
        “{$t.our-nick}, No notes for “weekly””);

$t.test(‘list topics’,
        “{$t.bot-nick}: list”,
        “{$t.our-nick}, No notes yet”);

# Creating notes

$t.test(‘note something’,
        “{$t.bot-nick}: blah foo”,
        “{$t.our-nick}, Noted!”);

$t.test(‘list topics (with notes)’,
        “{$t.bot-nick}: list”,
        “{$t.our-nick}, blah”);

$t.test(‘note something (shortcut)’,
        “weekly: Monday”,
        “{$t.our-nick}, Noted!”);

$t.test(‘list topics (with notes)’,
        “{$t.bot-nick}: list”,
        “{$t.our-nick}, blah weekly”);


$t.test(‘list notes’,
        “{$t.bot-nick}: blah”,
        /^<me($t)>‘, 1 note: ’<date>‘ <’<me($t)>‘>: foo’$/);

$t.test(‘list notes (shortcut)’,
        “weekly:”,
        /^<me($t)>‘, 1 note: ’<date>‘ <’<me($t)>‘>: Monday’$/);


# Clearing notes

my $moved;
my $moved-shortcut;

$t.test(‘clear’,
        “{$t.bot-nick}: clear blah”,
        /^<me($t)>‘, Moved existing notes to “blah_’<date>‘”’$
          {$moved=$<date>}/);

$t.test(‘clear (shortcut)’,
        “weekly: clear”,
        /^<me($t)>‘, Moved existing notes to “weekly_’<date>‘”’$
          {$moved-shortcut=$<date>}/);

$t.test(‘list moved notes’,
        “{$t.bot-nick}: blah_$moved”,
        /^<me($t)>‘, 1 note: ’<date>‘ <’<me($t)>‘>: foo’$/);

$t.test(‘list moved notes (can't use a shortcut, but still)’,
        “{$t.bot-nick}: weekly_$moved-shortcut”,
        /^<me($t)>‘, 1 note: ’<date>‘ <’<me($t)>‘>: Monday’$/);

$t.test(‘empty after clearing’,
        “{$t.bot-nick}: clear blah”,
        “{$t.our-nick}, No notes for “blah””);

$t.test(‘empty after clearing (shortcut)’,
        “weekly: clear”,
        “{$t.our-nick}, No notes for “weekly””);


$t.test(‘note something after clearing’,
        “{$t.bot-nick}: blah foo”,
        “{$t.our-nick}, Noted!”);

$t.test(‘note something after clearing (shortcut)’,
        “weekly: Monday”,
        “{$t.our-nick}, Noted!”);

$t.test(‘list notes after clearing’,
        “{$t.bot-nick}: blah”,
        /^<me($t)>‘, 1 note: ’<date>‘ <’<me($t)>‘>: foo’$/);

$t.test(‘list notes after clearing (shortcut)’,
        “weekly:”,
        /^<me($t)>‘, 1 note: ’<date>‘ <’<me($t)>‘>: Monday’$/);

$t.test(‘note something again’,
        “{$t.bot-nick}: blah bar”,
        “{$t.our-nick}, Noted!”);

$t.test(‘note something again (shortcut)’,
        “weekly: Tuesday”,
        “{$t.our-nick}, Noted!”);


$t.test(‘list two notes’,
        “{$t.bot-nick}: blah”,
        /^<me($t)>‘, 2 notes: ’<date>‘ <’<me($t)>‘>: foo  ;  ’<date>‘ <’<me($t)>‘>: bar’$/);

$t.test(‘list two notes (shortcut)’,
        “weekly:”,
        /^<me($t)>‘, 2 notes: ’<date>‘ <’<me($t)>‘>: Monday  ;  ’<date>‘ <’<me($t)>‘>: Tuesday’$/);

$t.test(‘note something big’,
        “{$t.bot-nick}: blah {‘z’ x 300}”,
        “{$t.our-nick}, Noted!”);

$t.test(‘note something big (shortcut)’,
        “weekly: {‘Z’ x 300}”,
        “{$t.our-nick}, Noted!”);

# DWIM

$t.test(‘clear …’,
        “{$t.bot-nick}: clear DWIM”,
        “{$t.our-nick}, No notes for “DWIM””);

$t.test(‘reset …’,
        “{$t.bot-nick}: reset DWIM”,
        “{$t.our-nick}, No notes for “DWIM””);

$t.test(‘delete …’,
        “{$t.bot-nick}: delete DWIM”,
        “{$t.our-nick}, No notes for “DWIM””);


$t.test(‘… clear’,
        “{$t.bot-nick}: DWIM clear”,
        “{$t.our-nick}, No notes for “DWIM””);

$t.test(‘… reset’,
        “{$t.bot-nick}: DWIM reset”,
        “{$t.our-nick}, No notes for “DWIM””);

$t.test(‘… delete’,
        “{$t.bot-nick}: DWIM delete”,
        “{$t.our-nick}, No notes for “DWIM””);

# TODO adapt test once the format is changed to markdown

$t.test(‘gist’,
        “{$t.bot-nick}: blah”,
        “{$t.our-nick}, 3 notes: https://whatever.able/fakeupload”);

$t.test-gist(‘correct gist’,
             %(‘result’ => /^<date>‘ <’$($t.our-nick)‘>: foo’\n
                             <date>‘ <’$($t.our-nick)‘>: bar’\n
                             <date>‘ <’$($t.our-nick)‘>: ’$(‘z’ x 300)$/));

$t.test(‘gist (shortcut)’,
        “weekly:”,
        “{$t.our-nick}, 3 notes: https://whatever.able/fakeupload”);

$t.test-gist(‘correct gist (shortcut)’,
             %(‘result’ => /^<date>‘ <’$($t.our-nick)‘>: Monday’\n
                             <date>‘ <’$($t.our-nick)‘>: Tuesday’\n
                             <date>‘ <’$($t.our-nick)‘>: ’$(‘Z’ x 300)$/));

$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

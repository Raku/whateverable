#!/usr/bin/env perl6
BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;
%*ENV<TESTABLE> = 1;

use lib <lib xt/lib>;
use Test;
use Testable;
use IRC::Client;

my $t = Testable.new: bot => ‘Tellable’;

$t.common-tests: help => ‘Like this: .tell AlexDaniel your bot is broken’;

$t.shortcut-tests: < to: tell: ask: seen:>,
                   < to, tell, ask, seen,>;

$t.test(‘fallback’,
        “{$t.bot-nick}: wazzup?”,
        “{$t.our-nick}, I cannot recognize this command. See wiki for some examples: https://github.com/perl6/whateverable/wiki/Tellable”);


$t.test(‘send a message’,
        “hello world”,);

# Seen

$t.test(‘.seen’,
        “.seen {$t.our-nick}”,
        /^ <me($t)>‘, I saw ’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘seen:’,
        “seen: {$t.our-nick}”,
        /^ <me($t)>‘, I saw ’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘seen without seen’,
        “{$t.bot-nick}: {$t.our-nick}”,
        /^ <me($t)>‘, I saw ’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘unnecessary seen’,
        “{$t.bot-nick}: seen {$t.our-nick}”,
        /^ <me($t)>‘, I saw ’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘no such nickname (seen)’,
        ‘.seen nobody’,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘seeing guests’,
        “.seen Guest35100”,
        “{$t.our-nick}, I haven't seen any guests around”);

# TODO it kinda works but for some reason not with long nicks
$t.test(‘.seen autocorrect’,
        “.seen x{$t.our-nick}”,
        “{$t.our-nick}, I haven't seen x{$t.our-nick} around, did you mean {$t.our-nick}?”);


# Seen normalization

$t.test(‘.seen (normalization, matrix users)’,
        “.seen {$t.our-nick}[m]”,
        /^ <me($t)>‘, I saw ’<me($t)>‘[m] 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, garbage at the end)’,
        “.seen {$t.our-nick}``|:”,
        /^ <me($t)>‘, I saw ’<me($t)>‘``| 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, garbage at the end, colon)’,
        “.seen {$t.our-nick}``|”,
        /^ <me($t)>‘, I saw ’<me($t)>‘``| 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, garbage at the beginning)’,
        “.seen `|{$t.our-nick}”,
        /^ <me($t)>‘, I saw `|’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, garbage at the end and beginning)’,
        “.seen `|{$t.our-nick}`|”,
        /^ <me($t)>‘, I saw `|’<me($t)>‘`| 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, hyphens)’,
        “.seen {$t.our-nick.comb.join: ‘-’}”,
        /^ <me($t)>‘, I saw ’“{$t.our-nick.comb.join: ‘-’}”
           ‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, numbers)’,
        “.seen {$t.our-nick}242134”,
        /^ <me($t)>‘, I saw ’<me($t)>‘242134 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );

$t.test(‘.seen (normalization, doubled letters)’,
        “.seen {$t.our-nick.comb.map({$_ x 2}).join}”,
        /^ <me($t)>‘, I saw ’“{$t.our-nick.comb.map({$_ x 2}).join}”
        ‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> hello world’ $/
       );


# CTCP ACTION

$t.test(:!both, ‘send a /me’, “\x[01]ACTION waves\x[01]”);

$t.test(:!both, ‘.seen a /me’,
        “.seen {$t.our-nick}”,
        /^ <me($t)>‘, I saw ’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: * ’<me($t)>‘ waves’ $/
       );


# Tell

$t.test(‘.tell’,
        ‘.tell nobody foo’,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘.to’,
        ‘.to nobody foo’,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘.ask’,
        ‘.ask nobody foo’,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘tell:’,
        ‘tell: nobody foo’,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘to:’,
        ‘to: nobody foo’,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘ask:’,
        ‘ask: nobody foo’,
        “{$t.our-nick}, I haven't seen nobody around”);


$t.test(‘tell without tell’,
        “{$t.bot-nick}: nobody foo”,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘unnecessary tell’,
        “{$t.bot-nick}: tell nobody foo”,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘unnecessary to’,
        “{$t.bot-nick}: to nobody foo”,
        “{$t.our-nick}, I haven't seen nobody around”);

$t.test(‘unnecessary ask’,
        “{$t.bot-nick}: ask nobody foo”,
        “{$t.our-nick}, I haven't seen nobody around”);


$t.test(:!both, ‘passing a message works’,
        “.tell {$t.our-nick} secret message”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘message delivery works’,
        ‘I'm back!’,
        /^ ‘2’\S+‘Z #whateverable_tellable6 <’<me($t)>‘> ’<me($t)>‘ secret message’ $/
       );

$t.test(:!both, ‘passing multiple messages (1)’,
        “.tell {$t.our-nick} secret message one”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘passing multiple messages (2)’,
        “.tell {$t.our-nick} secret message two”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘receiving multiple messages’,
        ‘I'm back!’,
        /^ ‘2’\S+‘Z #whateverable_tellable6 <’<me($t)>‘> ’<me($t)>‘ secret message one’ $/,
        /^ ‘2’\S+‘Z #whateverable_tellable6 <’<me($t)>‘> ’<me($t)>‘ secret message two’ $/,
       );


$t.test(:!both, ‘passing messages to the bot itself’,
        “.tell {$t.bot-nick} I love you”,
        “{$t.our-nick}, Thanks for the message”);

$t.test(‘passing messages to guests’,
        “.tell Guest35100 who are you?”,
        “{$t.our-nick}, Can't pass messages to guests”);

# Tell normalization

$t.test(:!both, ‘.tell (normalization, matrix users)’,
        “.tell {$t.our-nick}[m] whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, garbage at the end)’,
        “.tell {$t.our-nick}``| whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, garbage at the end, colon)’,
        “.tell {$t.our-nick}``|: whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, garbage at the beginning)’,
        “.tell `|{$t.our-nick} whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, garbage at the end and beginning)’,
        “.tell `|{$t.our-nick}`| whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, hyphens)’,
        “.tell {$t.our-nick.comb.join: ‘-’} whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, numbers)’,
        “.tell {$t.our-nick}242134 whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘.tell (normalization, doubled letters)’,
        “.tell {$t.our-nick.comb.map({$_ x 2}).join} whatever”,
        “{$t.our-nick}, I'll pass your message to {$t.our-nick}”);

$t.test(:!both, ‘receiving all messages (normalization)’,
        ‘I'm back!’,
        |(/^ ‘2’\S+‘Z #whateverable_tellable6 <’<me($t)>‘> ’\S+‘ whatever’ $/ xx 8)
        );

# TODO it kinda works but for some reason not with long nicks
$t.test(‘.tell autocorrect’,
        “.tell x{$t.our-nick} hello”,
        “{$t.our-nick}, I haven't seen x{$t.our-nick} around, did you mean {$t.our-nick}?”);


# Making sure that user tracking works

my $jnthn = IRC::Client.new(:nick(‘jnthn’)
                            :host<127.0.0.1> :port(%*ENV<TESTABLE_PORT>)
                            :channels<#whateverable_tellable6>);
start $jnthn.run;
sleep 1;

$jnthn.send: where => ‘#whateverable_tellable6’, text => ‘hello’;

$t.test(‘autosend doesn't mistrigger (join)’,
        ‘jnthn: hello’,);

$t.test(‘messages to other users are seen’,
        “.seen {$t.our-nick}”,
        /^ <me($t)>‘, I saw ’<me($t)>‘ 2’\S+‘Z in #whateverable_tellable6: <’<me($t)>‘> jnthn: hello’ $/
       );

$t.test(‘.seen is still working’,
        ‘.seen jnthn’,
        /^ <me($t)>‘, I saw jnthn 2’\S+‘Z in #whateverable_tellable6: <jnthn> hello’ $/
       );

$jnthn.nick: ‘notjnthn’;

$t.test(‘autosend works (nick change)’,
        ‘jnthn: where are you’,
        “{$t.our-nick}, I'll pass your message to jnthn”);

$jnthn.send: where => ‘#whateverable_tellable6’, text => ‘right here’;

$t.test(‘autosend doesn't mistrigger (nick change)’,
        ‘notjnthn: hello’,);

$t.test(‘autosend considers resolved nicknames’,
        ‘notjnthn``: hello’,);

$t.test(‘.seen is still working (again)’,
        ‘.seen notjnthn’,
        /^ <me($t)>‘, I saw notjnthn 2’\S+‘Z in #whateverable_tellable6: <notjnthn> right here’ $/
       );

$jnthn.part: ‘#whateverable_tellable6’;
$t.test(‘autosend works (part)’,
        ‘notjnthn: where???’,
        “{$t.our-nick}, I'll pass your message to notjnthn”);

$jnthn.join: ‘#whateverable_tellable6’;
$t.test(‘autosend doesn't mistrigger (join)’,
        ‘notjnthn: hello’,);

$jnthn.quit;
$t.test(‘autosend works (quit)’,
        ‘notjnthn: you've got to be kidding me’,
        “{$t.our-nick}, I'll pass your message to notjnthn”);


$t.last-test;
done-testing;
END $t.end;

# vim: expandtab shiftwidth=4 ft=perl6

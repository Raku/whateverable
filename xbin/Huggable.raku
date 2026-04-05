#!/usr/bin/env raku

use Whateverable;
use Whateverable::Bits;
use IRC::Client;

unit class Huggable does Whateverable;

method help($msg) {
    'Like this: .hug <nick>'
}

#| .hug
#| .hug <nick>...
#| hugs the sender if no nick is provided
multi method irc-privmsg-channel($msg where /^ \s* '.hug' \s* $<nicks>=(<.&irc-nick>* %% \s+) $/) {
    my $targets = $<nicks>.Str.trim || $msg.nick;
    my $text    = "\x[01]ACTION hugs $targets\x01" but RawAction;
    $.irc.send: :where($msg.channel), :$text;
}

#| huggable6: hug
#| huggable6: hug <nick>...
#| hugs the sender if no nick is provided
multi method irc-to-me($msg where /^ \s* 'hug' \s* $<nicks>=(<.&irc-nick>* %% \s+) $/) {
    my $targets = $<nicks>.Str.trim || $msg.nick;
    my $text    = "\x[01]ACTION hugs $targets\x01" but RawAction;
    $.irc.send: :where($msg.channel), :$text;
}

#| huggable6: <nick>...
multi method irc-to-me($msg where /^ \s* $<nicks>=(<.&irc-nick>* %% \s+) $/) {
    my $text = "\x[01]ACTION hugs {$msg.text.trim}\x01" but RawAction;
    $.irc.send: :where($msg.channel), :$text;
}

Huggable.new.selfrun: 'huggable6', [/ huggable6? <before ':'> /,
fuzzy-nick('huggable6', 2)]

#!/usr/bin/env perl6
use Whateverable;
use IRC::Client;

unit class Huggable does Whateverable

#| .hug
#| .hug <nick>...
#| hugs the sender if no nick is provided
method irc-privmsg-channel ($msg where / [\s|^] '.hug' [\s|$] /) {
    my $idx   = $msg.text.index('.hug') + 4;
    my $nicks = $msg.text.substr($idx).trim || $msg.nick;
    $.irc.send: :where($msg.channel), :text("hugs " ~ $nicks);
}

#| huggable6: hug
#| huggable6: hug <nick>...
#| hugs the sender if no nick is provided
multi method irc-to-me($msg where / [\s|^] 'hug' [\s|$] /) {
    my $idx   = $msg.text.index('hug') + 3;
    my $nicks = $msg.text.substr($idx).trim || $msg.nick;
    $.irc.send: :where($msg.channel), :text("hugs " ~ $nicks);
}

#| huggable6: <nick>...
multi method irc-to-me($msg) {
    $.irc.send: :where($msg.channel), :text("hugs " ~ $msg.text);
}

Huggable.new.selfrun: 'huggable6', [/ huggable6? <before ':'> /,
fuzzy-nick('huggable6', 2)]

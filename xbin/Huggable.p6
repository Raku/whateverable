use Whateverable;
use IRC::Client;

unit class Huggable does Whateverable

#| .hug
#| .hug <nick>...
method irc-privmsg-channel ($msg where / [\s|^] '.hug' [\s|$] /) {
    my $idx = $msg.text.index('.hug') + 4;
    $.irc.send: :where($msg.channel) :text("hugs" ~ ($msg.text.substr($idx) // ""));
}

#| huggable6: hug
#| huggable6: hug <nick>...
multi method irc-to-me($msg where / [\s|^] 'hug' [\s|$] /) {
    my $idx = $msg.text.index('hug') + 4;
    $.irc.send: :where($msg.channel) :text("hugs" ~ ($msg.text.substr($idx) // ""));
}

Huggable.new.selfrun: 'huggable6', [/ huggable6? <before ':'> /,
fuzzy-nick('huggable6', 2)]

use Whateverable;
use IRC::Client;

unit class Huggable does Whateverable

#| .hug
method irc-privmsg-channel ($msg where / [\s|^] '.hug' [\s|$] /) {
    my $idx = $msg.text.index('.hug') + 4;
    $.irc.send: :where($msg.channel) :text("hugs" ~ ($msg.text.substr($idx) // ""));
}

Huggable.new.selfrun: 'huggable6', [/ huggable6? <before ':'> /,
                                    fuzzy-nick('huggable6', 2)]

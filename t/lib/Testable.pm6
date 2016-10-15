use IRC::Client;
use Test;

class Testable {
    has $.our-nick;
    has $.bot-nick;

    has $!bot-proc;
    has $!irc-client;
    has $.messages;

    submethod BUILD(:$bot, :$!our-nick = ‘testable’) {
        my $ready  = Channel.new;
        $!messages = Channel.new;

        my $self = self;
        $!irc-client = IRC::Client.new(
            :nick($!our-nick) :host<127.0.0.1> :channels<#whateverable>
            :plugins(
                class {
                    method irc-privmsg-channel($m) { $self.messages.send: $m.args[1] if $m.nick eq $self.bot-nick; Nil }
                    method irc-join($m) { $ready.send: $m.nick if $++ == 1 }
                } )
        );
        start $!irc-client.run;

        $!bot-proc = Proc::Async.new($bot);
        $!bot-proc.start;

        start { sleep 20; $ready.send: False }
        $!bot-nick = $ready.receive;
        ok ?$!bot-nick, ‘bot joined the channel’;
    }

    method test($description, $command, *@expected, :$timeout = 10, :$delay = 3) {
        my @got;
        my $start = now;

        $!irc-client.send: :where<#whateverable> :text($command);
        sleep $delay if @expected == 0; # make it possible to check for no replies
        for ^@expected {
            my $message = $!messages.poll;
            if not defined $message {
                if now - $start > $timeout {
                    diag “Failed to get expected result in $timeout seconds”;
                    last;
                }
                sleep 0.1;
                redo;
            }
            @got.push: $message;
        }
        if @expected != @got or any(@got Z!~~ @expected) {
            diag “expected: {@expected.perl}”; # RT #129192
            diag “     got: {@got.perl}”;
            my $frame = callframe(2);
            diag “This test ran at {$frame.file} line {$frame.line}”;
            flunk $description;
            return;
        }
        pass $description;
    }

    method end {
        $!bot-proc.kill;
        $!irc-client.quit;
        sleep 2;
    }
}

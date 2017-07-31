use File::Directory::Tree;
use IRC::Client;
use Test;

my regex sha    is export { <.xdigit>**7..10 }
my regex me($t) is export { <{$t.our-nick}>  }

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
                    method irc-privmsg-channel($m) {
                        $self.messages.send: $m.args[1] if $m.nick eq $self.bot-nick;
                        Nil
                    }
                    method irc-join($m) {
                        $ready.send: $m.nick if $++ == 1
                    }
                }
            )
        );
        start $!irc-client.run;

        $!bot-proc = Proc::Async.new($bot);
        $!bot-proc.start;

        start { sleep 20; $ready.send: False }
        $!bot-nick = $ready.receive;
        ok ?$!bot-nick, ‘bot joined the channel’
    }

    method test($description, $command, *@expected, :$timeout = 11, :$delay = 3) {
        my $gists-path = “/tmp/whateverable/tist/”;
        rmtree $gists-path if $gists-path.IO ~~ :d;

        my @got;
        my $start = now;

        $!irc-client.send: :where<#whateverable> :text($command);
        sleep $delay if @expected == 0; # make it possible to check for no replies
        for ^@expected {
            my $message = $!messages.poll;
            if not defined $message {
                if now - $start > $timeout {
                    diag “Failed to get expected result in $timeout seconds”;
                    last
                }
                sleep 0.1;
                redo
            }
            @got.push: $message
        }
        cmp-ok @got, &[~~], @expected, $description
    }

    method test-gist($description, %files) {
        for %files.kv -> $file, $tests {
            my $path = “/tmp/whateverable/tist/$file”;
            ok $path.IO ~~ :f, “gist file $file exists”;
            cmp-ok slurp($path), &[~~], $_, “gist file {$file}: $description” for @$tests;
        }
    }

    method end {
        $!bot-proc.kill;
        $!irc-client.quit;
        sleep 2
    }
}

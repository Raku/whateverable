use File::Directory::Tree;
use IRC::Client;
use Test;

my regex sha    is export { <.xdigit>**7..10 }
my regex me($t) is export { $($t.our-nick)   }

class Testable {
    has $.bot;
    has $.our-nick;
    has $.bot-nick;

    has $!bot-proc;
    has $!irc-client;
    has $.messages;

    has $!first-test;
    has $!delay-channel;

    submethod BUILD(:$bot, :$our-nick = ‘testable’) {
        $!bot = $bot;
        my $ready  = Channel.new;
        $!messages = Channel.new;
        $!delay-channel = signal(SIGUSR1).Channel;

        my $self = self;
        $!irc-client = IRC::Client.new(
            :nick($our-nick ~ (^999999 .pick))
            :host<127.0.0.1>
            :channels(“#whateverable_{$bot.lc}6”)
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

        $!bot-proc = Proc::Async.new: ‘perl6’, ‘./bin/’ ~ $bot ~ ‘.p6’;
        $!bot-proc.bind-stdin: ‘config.json’.IO.open;
        start react {
            whenever $!bot-proc.start(:ENV(|%*ENV, PERL6LIB => ‘lib’)) {
                note “Bot process finished (exit code={.exitcode}, signal={.signal})”
            }
        }

        start { sleep 20; $ready.send: False }
        $!bot-nick = $ready.receive;
        $!our-nick = $!irc-client.servers.values[0].current-nick;
        ok ?$!bot-nick, ‘bot joined the channel’;
        is $!bot-nick, “{$bot.lc}6”, ‘bot nickname is expected’
    }

    method test(|c ($description, $command, *@expected, :$timeout is copy = 11, :$delay = 0.5)) {
        $timeout ×= 1.5 if %*ENV<HARNESS_ACTIVE>; # expect some load (relevant for parallelized tests)
        $!first-test = c without $!first-test;

        my $gists-path = “/tmp/whateverable/tist/$!bot-nick”;
        rmtree $gists-path if $gists-path.IO ~~ :d;

        my @got;
        my $start = now;

        $!irc-client.send: :where(“#whateverable_$!bot-nick”) :text($command);
        sleep $delay if @expected == 0; # make it possible to check for no replies
        my $lock-delay = 0;
        for ^@expected {
            my $message = $!messages.poll;
            if not defined $message {
                $lock-delay += 0.5 while $!delay-channel.poll;
                if now - $start - $lock-delay > $timeout {
                    diag “Failed to get expected result in {now - $start} seconds ($timeout nominal)”;
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
            my $path = “/tmp/whateverable/tist/$!bot-nick/$file”;
            ok $path.IO ~~ :f, “gist file $file exists”;
            cmp-ok slurp($path), &[~~], $_, “gist file {$file}: $description” for @$tests;
        }
    }

    method last-test {
        self.test(|$!first-test)
    }

    method end {
        my $answer;
        self.test(‘_’, “{$.bot-nick}: uptime”, {$answer=$_; True});
        mkdir ‘logs/tests’;
        my $logfile = sprintf “%s_uptime_%04d-%02d-%02d_%02d%02d.log”, $.bot.lc,
                      .year, .month, .day, .hour, .minute with now.DateTime;
        “logs/tests/$logfile”.IO.spurt: $answer;

        $!bot-proc.kill;
        $!irc-client.quit;
        sleep 2
    }

    method common-tests(:$help) {
        temp $!first-test;

        self.test(‘source link’,
                  “$.bot-nick: Source   ”,
                  “$.our-nick, https://github.com/perl6/whateverable”);

        self.test(‘source link’,
                  “$.bot-nick:   sourcE?  ”,
                  “$.our-nick, https://github.com/perl6/whateverable”);

        self.test(‘source link’,
                  “$.bot-nick:   URl ”,
                  “$.our-nick, https://github.com/perl6/whateverable”);

        self.test(‘source link’,
                  “$.bot-nick:  urL?   ”,
                  “$.our-nick, https://github.com/perl6/whateverable”);

        self.test(‘source link’,
                  “$.bot-nick: wIki”,
                  “$.our-nick, https://github.com/perl6/whateverable/wiki/$.bot”);

        self.test(‘source link’,
                  “$.bot-nick:   wiki? ”,
                  “$.our-nick, https://github.com/perl6/whateverable/wiki/$.bot”);


        self.test(‘help message’,
                  “$.bot-nick, helP”,
                  “$.our-nick, $help # See wiki for more examples: ”
                      ~ “https://github.com/perl6/whateverable/wiki/$.bot”);

        self.test(‘help message’,
                  “$.bot-nick,   HElp?  ”,
                  “$.our-nick, $help # See wiki for more examples: ”
                      ~ “https://github.com/perl6/whateverable/wiki/$.bot”);


        self.test(‘typoed name’,
                  “z{$.bot-nick.substr: 1}: source”, # mangle it just a little bit
                  “$.our-nick, https://github.com/perl6/whateverable”);

        self.test(‘no space after name (semicolon delimiter)’,
                  “{$.bot-nick}:url”,
                  “$.our-nick, https://github.com/perl6/whateverable”);

        self.test(‘no space after name (comma delimiter)’,
                  “$.bot-nick,url”,
                  “$.our-nick, https://github.com/perl6/whateverable”);


        self.test(‘uptime’,
                  “{$.bot-nick}: uptime”,
                  /{$.our-nick}‘,’ \s \d+ \s seconds/);
    }

    method shortcut-tests(@yes, @no) {
        temp $!first-test;

        for @yes {
            self.test(““$_” shortcut”,
                      “{$_}url”,
                      “$.our-nick, https://github.com/perl6/whateverable”);
            self.test(““$_ ” shortcut”,
                      “$_ url”,
                      “$.our-nick, https://github.com/perl6/whateverable”);
        }
        for @no {
            self.test(““$_” shortcut does not work”,
                      “$_ url”);
        }
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

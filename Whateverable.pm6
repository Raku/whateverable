# Copyright © 2016
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
#     Daniel Green <ddgreen@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use IRC::Client;

use File::Temp;
use JSON::Fast;
use Pastebin::Gist;
use HTTP::UserAgent;

constant RAKUDO = ‘./rakudo’.IO.absolute;
constant BUILDS = ‘./builds’.IO.absolute;
constant CONFIG = ‘./config.json’.IO.absolute;
constant SOURCE = ‘https://github.com/perl6/whateverable’;

%*ENV{‘RAKUDO_ERROR_COLOR’} = ‘’;

unit class Whateverable does IRC::Client::Plugin;

has $!timeout = 10;
has $!stdin = slurp ‘stdin’;

class ResponseStr is Str is export {
    # I know it looks crazy, but we will subclass a Str and hope
    # that our object propagates right to the filter.
    # Otherwise there is no way to get required data in the filter.
    has IRC::Client::Message $.message;
    has %.additional_files;
}

#↓ Matches only one space on purpose (for whitespace-only stdin)
multi method irc-to-me($msg where .text ~~ /:i^ [stdin] [‘ ’|‘=’] [clear|delete|reset|unset] $/) {
    $!stdin = slurp ‘stdin’;
    ResponseStr.new(value => “STDIN is reset to the default value”, message => $msg)
}

multi method irc-to-me($msg where .text ~~ /:i^ [stdin] [‘ ’|‘=’] $<stdin>=.* $/) {
    my ($ok, $new-stdin) = self.process-code(~$<stdin>, $msg);
    if $ok {
        $!stdin = $new-stdin;
        return ResponseStr.new(value => “STDIN is set to «{$!stdin}»”, message => $msg)
    } else {
        return ResponseStr.new(value => “Nothing done”, message => $msg)
    }
}

multi method irc-to-me($msg where .text ~~ /:i^ [source|url] ‘?’? $/) {
    ResponseStr.new(value => SOURCE, message => $msg)
}

multi method irc-to-me($msg where .text ~~ /:i^ help ‘?’? $/) {
    ResponseStr.new(value => self.help($msg), message => $msg)
}

multi method irc-privmsg-me($msg) {
    ResponseStr.new(value => ‘Sorry, it is too private here’, message => $msg) # See GitHub issue #16
}

method help($message) { “See {SOURCE}” } # override this in your bot

method get-output(*@run-args, :$timeout = $!timeout, :$stdin) {
    my $out = Channel.new; # TODO switch to some Proc :merge thing once it is implemented
    my $proc = Proc::Async.new(|@run-args, :w(defined $stdin));
    $proc.stdout.tap(-> $v { $out.send: $v });
    $proc.stderr.tap(-> $v { $out.send: $v });

    my $s-start = now;
    my $promise = $proc.start;
    if defined $stdin {
        $proc.print: $stdin;
        $proc.close-stdin;
    }
    await Promise.anyof(Promise.in($timeout), $promise);
    my $s-end = now;

    if not $promise.status ~~ Kept { # timed out
        $proc.kill; # TODO sends HUP, but should kill the process tree instead
        $out.send: “«timed out after $timeout seconds, output»: ”;
    }
    $out.close;
    return ($out.list.join.chomp, $promise.result.exitcode, $promise.result.signal, $s-end - $s-start)
}

method run-snippet($full-commit-hash, $file, :$timeout = $!timeout) {
    self.get-output(“{BUILDS}/$full-commit-hash/bin/perl6”, $file, stdin => $!stdin, timeout => $timeout);
}

method to-full-commit($commit) {
    my $old-dir = $*CWD;
    chdir RAKUDO;
    LEAVE chdir $old-dir;

    return if run(‘git’, ‘rev-parse’, ‘--verify’, $commit).exitcode != 0; # make sure that $commit is valid

    my ($result, $exit-status, $exit-signal, $time)
         = self.get-output(‘git’, ‘rev-list’, ‘-1’, $commit); # use rev-list to handle tags

    return if $exit-status != 0;
    return $result;
}

method write-code($code) {
    my ($filename, $filehandle) = tempfile :!unlink;
    $filehandle.print: $code;
    $filehandle.close;
    return $filename
}

method process-url($url, $message) {
    my $ua = HTTP::UserAgent.new;
    my $response = $ua.get($url);

    if not $response.is-success {
        return (0, ‘It looks like a URL, but for some reason I cannot download it’
                       ~ “ (HTTP status line is {$response.status-line}).”);
    }
    if $response.field(‘content-type’) ne ‘text/plain; charset=utf-8’ {
        return (0, “It looks like a URL, but mime type is ‘{$response.field(‘content-type’)}’”
                       ~ ‘ while I was expecting ‘text/plain; charset=utf-8’.’
                       ~ ‘ I can only understand raw links, sorry.’);
    }
    my $body = $response.content;

    $message.reply: ‘Successfully fetched the code from the provided URL.’;
    return (1, $body)
}

method process-code($code is copy, $message) {
    if ($code ~~ m{^ ‘http’ s? ‘://’ } ) {
        my ($succeeded, $response) = self.process-url($code, $message);
        return (0, $response) unless $succeeded;
        $code = $response;
    } else {
        $code .= subst: :g, ‘␤’, “\n”;
    }
    return (1, $code)
}

multi method filter($response where (.chars > 300 or .?additional_files)) {
    if $response ~~ ResponseStr {
        self.upload({‘result’ => $response, ‘query’ => $response.message.text, $response.?additional_files},
                    description => $response.message.server.current-nick, :public);
    } else {
        self.upload({‘result’ => $response}, description => ‘Whateverable’, :public);
    }
}

multi method filter($text) {
    $text.trans:
        |((^32)».chr Z=> (0x2400..*).map(*.chr)), # convert all unreadable ASCII crap
        “\n” => ‘␤’, 127.chr => ‘␡’;
}

method upload(%files is copy, :$description = ‘’, Bool :$public = True) {
    state $config = from-json slurp CONFIG;
    %files = %files.pairs.map: { .key => %( ‘content’ => .value ) }; # github format

    my $gist = Pastebin::Gist.new(token => $config<access_token>);
    return $gist.paste(%files, desc => $description, public => $public);
}

method selfrun($nick is copy, @alias?) {
    $nick ~= ‘test’ if %*ENV<DEBUGGABLE>;
    .run with IRC::Client.new(
        :$nick
        :userreal($nick.tc)
        :username($nick.tc)
        :@alias
        :host<irc.freenode.net>
        :channels(%*ENV<DEBUGGABLE> ?? <#whateverable> !! <#perl6 #perl6-dev #whateverable>)
        :debug(?%*ENV<DEBUGGABLE>)
        :plugins(self)
        :filters( -> |c { self.filter(|c) } )
    )
}

# vim: expandtab shiftwidth=4 ft=perl6

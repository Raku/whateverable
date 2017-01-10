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
use IRC::Client::Message;

use File::Directory::Tree;
use File::Temp;
use JSON::Fast;
use Pastebin::Gist;
use HTTP::UserAgent;
use Text::Diff::Sift4;
use IRC::TextColor;
use Terminal::ANSIColor;

constant Message = IRC::Client::Message;

constant RAKUDO = ‘./rakudo’.IO.absolute;
constant CONFIG = ‘./config.json’.IO.absolute;
constant SOURCE = ‘https://github.com/perl6/whateverable’;
constant WORKING-DIRECTORY = ‘.’; # TODO not supported yet
constant ARCHIVES-LOCATION = “{WORKING-DIRECTORY}/builds/rakudo-moar”.IO.absolute;
constant BUILDS-LOCATION   = ‘/tmp/whateverable/rakudo-moar’;
constant LEGACY-BUILDS-LOCATION = “{WORKING-DIRECTORY}/builds”.IO.absolute;

# %*ENV{‘RAKUDO_ERROR_COLOR’} = ‘’;

unit class Whateverable does IRC::Client::Plugin;

constant MESSAGE-LIMIT is export = 260;
constant COMMITS-LIMIT = 500;

has $.timeout is rw = 10;
has $!stdin = slurp ‘stdin’;
has %!bad-releases = '2016.01' => True, '2016.01.1' => True;
has $.always-upload is rw = False;

class ResponseStr is Str is export {
    # I know it looks crazy, but we will subclass a Str and hope
    # that our object propagates right to the filter.
    # Otherwise there is no way to get required data in the filter.
    has IRC::Client::Message $.message;
    has %.additional-files;
}

#↓ Matches only one space on purpose (for whitespace-only stdin)
multi method irc-to-me(Message $msg where .text ~~ /:i^ [stdin] [‘ ’|‘=’] [clear|delete|reset|unset] $/) {
    $!stdin = slurp ‘stdin’;
    ResponseStr.new(value => “STDIN is reset to the default value”, message => $msg)
}

multi method irc-to-me(Message $msg where .text ~~ /:i^ [stdin] [‘ ’|‘=’] $<stdin>=.* $/) {
    my ($ok, $new-stdin) = self.process-code(~$<stdin>, $msg);
    if $ok {
        $!stdin = $new-stdin;
        return ResponseStr.new(value => “STDIN is set to «{$!stdin}»”, message => $msg)
    } else {
        return ResponseStr.new(value => “Nothing done”, message => $msg)
    }
}

multi method irc-to-me(Message $msg where .text ~~ /:i^ [source|url] ‘?’? $/) {
    ResponseStr.new(value => SOURCE, message => $msg)
}

multi method irc-to-me(Message $msg where .text ~~ /:i^ help ‘?’? $/) {
    ResponseStr.new(value => self.help($msg), message => $msg)
}

multi method irc-notice-me($msg) {
    ResponseStr.new(value => ‘Sorry, it is too private here’, message => $msg) # See GitHub issue #16
}

multi method irc-privmsg-me($msg) {
    ResponseStr.new(value => ‘Sorry, it is too private here’, message => $msg) # See GitHub issue #16
}

method help($message) { “See {SOURCE}” } # override this in your bot

method get-short-commit($original-commit) {
    $original-commit ~~ /^ <xdigit> ** 7..40 $/ ?? $original-commit.substr(0, 7) !! $original-commit;
}

method get-output(*@run-args, :$timeout = $!timeout, :$stdin) {
    my $out = Channel.new; # TODO switch to some Proc :merge thing once it is implemented
    my $proc = Proc::Async.new(|@run-args, :w(defined $stdin));
    $proc.stdout.tap(-> $v { $out.send: $v });
    $proc.stderr.tap(-> $v { $out.send: $v });

    my $s-start = now;
    my $promise = $proc.start(scheduler => BEGIN ThreadPoolScheduler.new);
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
    try sink await $promise; # wait until it is actually stopped
    $out.close;
    return $out.list.join.chomp, $promise.result.exitcode, $promise.result.signal, $s-end - $s-start
}

method build-exists($full-commit-hash) {
    “{ARCHIVES-LOCATION}/$full-commit-hash.zst”.IO ~~ :e
}

method get-similar($tag-or-hash, @other?) {
    my $old-dir = $*CWD;
    LEAVE chdir $old-dir;
    chdir RAKUDO;

    my @options = @other;
    my @tags = self.get-output(‘git’, ‘tag’, ‘--format=%(*objectname)/%(objectname)/%(refname:strip=2)’,
                               ‘--sort=-taggerdate’)[0].lines
                               .map(*.split(‘/’))
                               .grep({ self.build-exists(.[0] || .[1]) })
                               .map(*[2]);
    my @commits = self.get-output(‘git’, ‘rev-list’, ‘--all’, ‘--since=2014-01-01’)[0]
                      .lines.map(*.substr: 0, $tag-or-hash.chars < 7 ?? 7 !! $tag-or-hash.chars);

    # flat(@options, @tags, @commits).min: { sift4($_, $tag-or-hash, 5) }
    my $ans = ‘HEAD’;
    my $ans_min = Inf;

    for flat(@options, @tags, @commits) {
        my $dist = sift4($_, $tag-or-hash, 5, 5);
        if $dist < $ans_min {
            $ans = $_;
            $ans_min = $dist;
        }
    }
    $ans
}

method run-smth($full-commit-hash, $code) {
    # lock on the destination directory to make
    # sure that other bots will not get in our way.
    while run(‘mkdir’, ‘--’, “{BUILDS-LOCATION}/$full-commit-hash”).exitcode != 0 {
        sleep 0.5;
        # Uh, wait! Does it mean that at the same time we can use only one
        # specific build? Yes, and you will have to wait until another bot
        # deletes the directory so that you can extract it back again…
        # There are some ways to make it work, but don't bother. Instead,
        # we should be doing everything in separate isolated containers (soon),
        # so this problem will fade away.
    }
    my $proc = run(:out, :bin, ‘pzstd’, ‘-dqc’, ‘--’, “{ARCHIVES-LOCATION}/$full-commit-hash.zst”);
    run(:in($proc.out), :bin, ‘tar’, ‘x’, ‘--absolute-names’);

    my $return = $code(“{BUILDS-LOCATION}/$full-commit-hash”);

    rmtree “{BUILDS-LOCATION}/$full-commit-hash”;

    $return
}

method run-snippet($full-commit-hash, $file, :$timeout = $!timeout) {
    self.run-smth: $full-commit-hash, {
        my @out;
        if “{BUILDS-LOCATION}/$full-commit-hash/bin/perl6”.IO !~~ :e {
            @out = ‘Commit exists, but a perl6 executable could not be built for it’, -1, -1;
        } else {
            @out = self.get-output(“{BUILDS-LOCATION}/$full-commit-hash/bin/perl6”,
                                   ‘--setting=RESTRICTED’, ‘--’, $file, :$!stdin, :$timeout);
        }
        rmtree “{BUILDS-LOCATION}/$full-commit-hash”;
        @out
    }
}

method get-commits($config) {
    my $old-dir = $*CWD;
    LEAVE chdir $old-dir;
    my @commits;

    if $config.contains(‘,’) {
        @commits = $config.split: ‘,’;
    } elsif $config ~~ /^ $<start>=\S+ ‘..’ $<end>=\S+ $/ {
        chdir RAKUDO; # goes back in LEAVE
        if run(:out(Nil), ‘git’, ‘rev-parse’, ‘--verify’, $<start>).exitcode != 0 {
            return “Bad start, cannot find a commit for “$<start>””;
        }
        if run(:out(Nil), ‘git’, ‘rev-parse’, ‘--verify’, $<end>).exitcode   != 0 {
            return “Bad end, cannot find a commit for “$<end>””;
        }
        my ($result, $exit-status, $exit-signal, $time) =
          self.get-output(‘git’, ‘rev-list’, “$<start>^..$<end>”); # TODO unfiltered input
        return ‘Couldn't find anything in the range’ if $exit-status != 0;
        @commits = $result.lines;
        my $num-commits = @commits.elems;
        return “Too many commits ($num-commits) in range, you're only allowed {COMMITS-LIMIT}” if $num-commits > COMMITS-LIMIT;
    } elsif $config ~~ /:i releases | « v? 6 \.? c » / {
        @commits = self.get-tags('2015-12-25');
    } elsif $config ~~ /:i all / {
        @commits = self.get-tags('2014-01-01');
    } elsif $config ~~ /:i compare \s $<commit>=\S+ / {
        @commits = $<commit>;
    } else {
        @commits = $config;
    }

    return Nil, |@commits;
}

method get-tags($date) {
    my $old-dir = $*CWD;
    chdir RAKUDO;
    LEAVE chdir $old-dir;

    my @tags = <HEAD>;
    my %seen;
    for self.get-output('git', 'log', '--pretty="%d"', '--tags', '--no-walk', "--since=$date").lines -> $tag {
        if $tag ~~ /:i "tag:" \s* ((\d\d\d\d\.\d\d)[\.\d\d?]?) / and
           not %!bad-releases{$0}:exists and
           not %seen{$0[0]}++
        {
             @tags.push($0)
        }
    }

    return @tags.reverse;
}

method to-full-commit($commit, :$short = False) {
    my $old-dir = $*CWD;
    chdir RAKUDO;
    LEAVE chdir $old-dir;

    return if run(‘git’, ‘rev-parse’, ‘--verify’, $commit).exitcode != 0; # make sure that $commit is valid

    my ($result, $exit-status, $exit-signal, $time)
         = self.get-output( |(‘git’, ‘rev-list’, ‘-1’, # use rev-list to handle tags
                              ($short ?? ‘--abbrev-commit’ !! Empty), $commit) );

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
    if not $response.content-type.contains(any(‘text/plain’, ‘perl’)) {
        return (0, “It looks like a URL, but mime type is ‘{$response.content-type}’”
                       ~ ‘ while I was expecting something with ‘text/plain’ or ‘perl’’
                       ~ ‘ in it. I can only understand raw links, sorry.’);
    }
    my $body = $response.decoded-content;

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

multi method filter($response where ($!always-upload and $response.contains(“\n”)
                                     or .encode.elems > MESSAGE-LIMIT or .?additional-files)) {
    if $response ~~ ResponseStr {
        self.upload({‘result’ => colorstrip($response),
                     ‘query’ => $response.message.text, $response.?additional-files},
                    description => $response.message.server.current-nick, :public);
    } else {
        self.upload({‘result’ => colorstrip($response)},
                     description => ‘Whateverable’, :public);
    }
}

multi method filter($text is copy) {
    ansi-to-irc($text).trans:
        “\n” => ‘␤’,
        3.chr => 3.chr, 0xF.chr => 0xF.chr, # keep these for IRC colors
        |((^32)».chr Z=> (0x2400..*).map(*.chr)), # convert all unreadable ASCII crap
        127.chr => ‘␡’, /<:Cc>/ => ‘␦’;
}

method upload(%files is copy, :$description = ‘’, Bool :$public = True) {
    return ‘https://whatever.able/fakeupload’ if %*ENV<TESTABLE>;

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
        :password(?%*ENV<TESTABLE> ?? ‘’ !! from-json(slurp CONFIG)<irc-login irc-password>.join(‘:’))
        :@alias
        :host(%*ENV<TESTABLE> ?? ‘127.0.0.1’ !! ‘irc.freenode.net’)
        :channels(%*ENV<DEBUGGABLE> ?? <#whateverable> !! <#perl6 #perl6-dev #whateverable>)
        :debug(?%*ENV<DEBUGGABLE>)
        :plugins(self)
        :filters( -> |c { self.filter(|c) } )
    )
}

sub fuzzy-nick($nick, $distance) is export {
    / \w+ <?{ sift4(~$/, $nick, 5) ~~ 1..$distance }> /
}

# vim: expandtab shiftwidth=4 ft=perl6

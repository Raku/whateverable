# Copyright © 2016-2017
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
# Copyright © 2016
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

use File::Directory::Tree;
use File::Temp;
use HTTP::UserAgent;
use IRC::Client::Message;
use IRC::Client;
use IRC::TextColor;
use JSON::Fast;
use Number::Denominate;
use Pastebin::Gist;
use Terminal::ANSIColor;
use Text::Diff::Sift4;

use Misc;

our $RAKUDO = ‘./data/rakudo-moar’.IO.absolute;
constant MOARVM = ‘./data/moarvm’.IO.absolute;
constant CONFIG = ‘./config.json’.IO.absolute;
constant SOURCE = ‘https://github.com/perl6/whateverable’;
constant WIKI   = ‘https://github.com/perl6/whateverable/wiki/’;
constant WORKING-DIRECTORY = ‘.’.IO.absolute; # TODO not supported yet
constant ARCHIVES-LOCATION = “{WORKING-DIRECTORY}/data/builds”.IO.absolute;
constant BUILDS-LOCATION   = ‘/tmp/whateverable/’.IO.absolute;

constant MESSAGE-LIMIT is export = 260;
constant COMMITS-LIMIT = 500;
constant PARENTS = ‘AlexDaniel’, ‘MasterDuke’;

constant Message = IRC::Client::Message;

unit role Whateverable[:$default-timeout = 10] does IRC::Client::Plugin does Helpful;

has $!stdin = slurp ‘stdin’;
has $!bad-releases = set ‘2016.01’, ‘2016.01.1’;

method TWEAK {
    # wrap around everything to catch exceptions
    once { # per class
        self.^lookup(‘irc-to-me’).wrap: sub ($self, $msg) {
            try { with (callsame) { return $_ but Reply($msg) } else { return } }
            $self.handle-exception: $!, $msg
        };

        self.^lookup(‘filter’).wrap: sub ($self, $response) {
            my &filter = nextcallee;
            try { return filter $self, $response }
            try { return filter $self, $self.handle-exception($!, $response.?msg) }
            ‘Sorry kid, that's not my department.’
        };
    }
    # TODO roles should not have TWEAK method
}

method handle-exception($exception, $msg?) {
    CATCH { # exception handling is too fat, so let's do this also…
        .say;
        return ‘Exception was thrown while I was trying to handle another exception…’
             ~ ‘ What are they gonna do to me, Sarge? What are they gonna do⁈’
    }
    if $exception ~~ Whateverable::X::HandleableAdHoc { # oh, it's OK!
        return $exception.message but Reply($_) with $msg;
        return $exception.message
    }

    say $exception;
    with $msg {
        if .channel ne ‘#whateverable’ {
            .irc.send-cmd: ‘PRIVMSG’, .channel, “I'm acting stupid on {.channel}. Help me.”,
                           :server(.server), :prefix(PARENTS.join(‘, ’) ~ ‘: ’)
        }
    }

    my ($text, @files) = flat self.awesomify-exception: $exception;
    @files .= map({ ‘uncommitted-’ ~ .split(‘/’).tail => .IO.slurp });
    @files.push: ‘|git-diff-HEAD.patch’ => run(:out, ‘git’, ‘diff’, ‘HEAD’).out.slurp-rest if @files;
    @files.push: ‘result.md’ => $text;

    my $return = (‘’ but FileStore(%@files))
      but PrettyLink({“No! It wasn't me! It was the one-armed man! Backtrace: $_”});
    # https://youtu.be/MC6bzR9qmxM?t=97
    $return = $return but Reply($_) with $msg;
    $return
}

method awesomify-exception($exception) {
    my @local-files;
    my $sha = run(:out, ‘git’, ‘rev-parse’, ‘--verify’, ‘HEAD’).out.slurp-rest;
    ‘<pre>’ ~
    $exception.gist.lines.map({
        # TODO Proper way to get data out of exceptions?
        # For example, right now it is broken for paths with spaces
        when /:s ^([\s**2|\s**6]in \w+ \S* at “{WORKING-DIRECTORY}/”?)$<path>=[\S+](
                                         [<.ws>‘(’<-[)]>+‘)’]? line )$<line>=[\d+]$/ {
            my $status = run :out, ‘git’, ‘status’, ‘--porcelain’, ‘--untracked-files=no’,
                                   ‘--’, ~$<path>;
            proceed if !$status && !%*ENV<DEBUGGABLE>; # not a repo file and not in the debug mode
            my $private-debugging = !$status;
            $status = $status.out.slurp-rest;
            my $uncommitted = $status && !$status.starts-with: ‘  ’; # not committed yet
            @local-files.push: ~$<path> if $uncommitted || $private-debugging;
            my $href = $uncommitted || $private-debugging
              ?? “#file-uncommitted-{$<path>.split(‘/’).tail.lc.trans(‘.’ => ‘-’)}-” # TODO not perfect but good enough
              !! “{SOURCE}/blob/$sha/{markdown-escape $<path>}#”;
            $href ~= “L$<line>”;

            markdown-escape($0) ~
            # let's hope for the best ↓
            “<a href="$href">{$<path>}</a>” ~
            markdown-escape($1 ~ $<line>) ~
            ($uncommitted ?? ‘ (⚠ uncommitted)’ !! ‘’)
        }
        default { $_ }
    }).join(“\n”)
    ~ ‘</pre>’, @local-files
}

multi method irc-to-me(Message $msg where .text ~~
                       #↓ Matches only one space on purpose (for whitespace-only stdin)
                       /:i^ [stdin] [‘ ’|‘=’] [clear|delete|reset|unset] $/) {
    $!stdin = slurp ‘stdin’;
    ‘STDIN is reset to the default value’
}

multi method irc-to-me(Message $msg where .text ~~ /:i^ [stdin] [‘ ’|‘=’] $<stdin>=.* $/) {
    $!stdin = self.process-code: ~$<stdin>, $msg;
    “STDIN is set to «{shorten $!stdin, 200}»” # TODO is 200 a good limit?
}

multi method irc-to-me(Message $    where .text ~~ /:i^ [source|url] ‘?’? $/ --> SOURCE) {}
multi method irc-to-me(Message $    where .text ~~ /:i^ wiki ‘?’? $/) { self.get-wiki-link }
multi method irc-to-me(Message $msg where .text ~~ /:i^ help ‘?’? $/) {
    self.help($msg) ~ “ # See wiki for more examples: {self.get-wiki-link}”
}
multi method irc-to-me(Message $msg where .text ~~ /:i^ uptime $/) {
    ~denominate now - INIT now
}
multi method irc-notice-me( $ --> ‘Sorry, it is too private here’) {} # TODO issue #16
multi method irc-privmsg-me($ --> ‘Sorry, it is too private here’) {} # TODO issue #16
multi method irc-to-me($) {
    ‘I cannot recognize this command. See wiki for some examples: ’ ~ self.get-wiki-link
}

method get-wiki-link { WIKI ~ self.^name }

method get-short-commit($original-commit) { # TODO not an actual solution tbh
    $original-commit ~~ /^ <xdigit> ** 7..40 $/
    ?? $original-commit.substr(0, 7)
    !! $original-commit
}

method get-output(*@run-args, :$timeout = $default-timeout, :$stdin, :$ENV, :$cwd = $*CWD) {
    my @lines;
    my $proc = Proc::Async.new: |@run-args, w => defined $stdin;
    my $s-start = now;
    my $result;
    my $s-end;

    react {
        whenever $proc.stdout { @lines.push: $_ }; # RT #131763
        whenever $proc.stderr { @lines.push: $_ };
        whenever Promise.in($timeout) {
            $proc.kill; # TODO sends HUP, but should kill the process tree instead
            @lines.push: “«timed out after $timeout seconds»”
        }
        whenever $proc.start: :$ENV, :$cwd { #: scheduler => BEGIN ThreadPoolScheduler.new { # TODO do we need to set scheduler?
            $result = $_;
            $s-end = now;
            done
        }
        with $stdin {
            whenever $proc.print: $_ { $proc.close-stdin }
        }
    }
    %(
        output    => @lines.join.chomp,
        exit-code => $result.exitcode,
        signal    => $result.signal,
        time      => $s-end - $s-start,
    )
}

method build-exists($full-commit-hash, :$backend=‘rakudo-moar’) {
    “{ARCHIVES-LOCATION}/$backend/$full-commit-hash.zst”.IO ~~ :e
    or
    “{ARCHIVES-LOCATION}/$backend/$full-commit-hash”.IO ~~ :e # long-term storage (symlink to a large archive)
}

method get-similar($tag-or-hash, @other?, :$repo=$RAKUDO) {
    my @options = @other;
    my @tags = self.get-output(cwd => $repo, ‘git’, ‘tag’,
                               ‘--format=%(*objectname)/%(objectname)/%(refname:strip=2)’,
                               ‘--sort=-taggerdate’)<output>.lines
                               .map(*.split(‘/’))
                               .grep({ self.build-exists: .[0] || .[1] })
                               .map(*[2]);

    my $cutoff = $tag-or-hash.chars max 7;
    my @commits = self.get-output(cwd => $repo, ‘git’, ‘rev-list’,
                                  ‘--all’, ‘--since=2014-01-01’)<output>
                      .lines.map(*.substr: 0, $cutoff);

    # flat(@options, @tags, @commits).min: { sift4($_, $tag-or-hash, 5, 8) }
    my $ans = ‘HEAD’;
    my $ans_min = ∞;

    for flat @options, @tags, @commits {
        my $dist = sift4 $_, $tag-or-hash, $cutoff;
        if $dist < $ans_min {
            $ans = $_;
            $ans_min = $dist;
        }
    }
    $ans
}

method run-smth($full-commit-hash, $code, :$backend=‘rakudo-moar’) {
    my $build-path   = “{  BUILDS-LOCATION}/$backend/$full-commit-hash”;
    my $archive-path = “{ARCHIVES-LOCATION}/$backend/$full-commit-hash.zst”;
    my $archive-link = “{ARCHIVES-LOCATION}/$backend/$full-commit-hash”;

    # lock on the destination directory to make
    # sure that other bots will not get in our way.
    while run(‘mkdir’, ‘--’, $build-path).exitcode ≠ 0 {
        sleep 0.5;
        # Uh, wait! Does it mean that at the same time we can use only one
        # specific build? Yes, and you will have to wait until another bot
        # deletes the directory so that you can extract it back again…
        # There are some ways to make it work, but don't bother. Instead,
        # we should be doing everything in separate isolated containers (soon),
        # so this problem will fade away.
    }
    if $archive-path.IO ~~ :e {
        my $proc = run :out, :bin, ‘pzstd’, ‘-dqc’, ‘--’, $archive-path;
        run :in($proc.out), :bin, ‘tar’, ‘x’, ‘--absolute-names’;
    } else {
        my $proc = run :out, :bin, ‘lrzip’, ‘-dqo’, ‘-’, ‘--’, $archive-link;
        run :in($proc.out), :bin, ‘tar’, ‘--extract’, ‘--absolute-names’, ‘--’, $build-path;
    }

    my $return = $code($build-path); # basically, we wrap around $code
    rmtree $build-path;
    $return
}

method run-snippet($full-commit-hash, $file, :$backend=‘rakudo-moar’, :$timeout = $default-timeout, :$ENV) {
    self.run-smth: :$backend, $full-commit-hash, -> $path {
        “$path/bin/perl6”.IO !~~ :e
        ?? %(output => ‘Commit exists, but a perl6 executable could not be built for it’,
             exit-code => -1, signal => -1, time => -1,)
        !! self.get-output: “$path/bin/perl6”, ‘--setting=RESTRICTED’, ‘--’,
                            $file, :$!stdin, :$timeout, :$ENV
    }
}

method get-commits($_, :$repo=$RAKUDO) {
    return .split: /‘,’\s*/ if .contains: ‘,’;

    if /^ $<start>=\S+ ‘..’ $<end>=\S+ $/ {
        if run(:out(Nil), :err(Nil), :cwd($repo),
               ‘git’, ‘rev-parse’, ‘--verify’, $<start>).exitcode ≠ 0 {
            grumble “Bad start, cannot find a commit for “$<start>””
        }
        if run(:out(Nil), :err(Nil), :cwd($repo),
               ‘git’, ‘rev-parse’, ‘--verify’, $<end>).exitcode   ≠ 0 {
            grumble “Bad end, cannot find a commit for “$<end>””
        }
        my $result = self.get-output: :cwd($repo), ‘git’, ‘rev-list’, ‘--reverse’, “$<start>^..$<end>”; # TODO unfiltered input
        grumble ‘Couldn't find anything in the range’ if $result<exit-code> ≠ 0;
        my @commits = $result<output>.lines;
        if @commits.elems > COMMITS-LIMIT {
            grumble “Too many commits ({@commits.elems}) in range, you're only allowed {COMMITS-LIMIT}”
        }
        return @commits
    }
    return self.get-tags: ‘2015-12-24’, :$repo if /:i ^ [ releases | v? 6 ‘.’? c ] $/;
    return self.get-tags: ‘2014-01-01’, :$repo if /:i ^   all                      $/;
    return ~$<commit>                          if /:i ^   compare \s $<commit>=\S+ $/;
    return $_
}

method get-tags($date, :$repo=$RAKUDO) {
    my @tags = <HEAD>;
    my %seen;
    for self.get-output(cwd => $repo, ‘git’, ‘log’, ‘--pretty="%d"’,
                        ‘--tags’, ‘--no-walk’, “--since=$date”)<output>.lines -> $tag {
        next unless $tag ~~ /:i ‘tag:’ \s* ((\d\d\d\d\.\d\d)[\.\d\d?]?) /; # TODO use tag -l
        next if $!bad-releases{$0}:exists;
        next if %seen{$0[0]}++;
        @tags.push($0)
    }

    @tags.reverse
}

method to-full-commit($commit, :$short=False, :$repo=$RAKUDO) {
    return if run(:out(Nil), :err(Nil), :cwd($repo),
                  ‘git’, ‘rev-parse’, ‘--verify’, $commit).exitcode ≠ 0; # make sure that $commit is valid

    my $result = self.get-output: cwd => $repo,
                                  |(‘git’, ‘rev-list’, ‘-1’, # use rev-list to handle tags
                                    ($short ?? ‘--abbrev-commit’ !! Empty), $commit);

    return if     $result<exit-code> ≠ 0;
    return unless $result<output>;
    $result<output>
}

method write-code($code) {
    my ($filename, $filehandle) = tempfile :!unlink;
    $filehandle.print: $code;
    $filehandle.close;
    $filename
}

method process-url($url, $message) {
    my $ua = HTTP::UserAgent.new;
    my $response;
    try {
        $response = $ua.get: $url;
        CATCH {
            grumble ‘It looks like a URL, but for some reason I cannot download it’
                    ~ “ ({.message})”
        }
    }
    if not $response.is-success {
        grumble ‘It looks like a URL, but for some reason I cannot download it’
                ~ “ (HTTP status line is {$response.status-line}).”
    }
    if not $response.content-type.contains: ‘text/plain’ | ‘perl’ {
        grumble “It looks like a URL, but mime type is ‘{$response.content-type}’”
                ~ ‘ while I was expecting something with ‘text/plain’ or ‘perl’’
                ~ ‘ in it. I can only understand raw links, sorry.’
    }

    my $body = $response.decoded-content;
    $message.reply: ‘Successfully fetched the code from the provided URL.’;
    return $body
}

method process-code($code is copy, $message) {
    $code ~~ m{^ ( ‘http’ s? ‘://’ \S+ ) }
    ?? self.process-url(~$0, $message)
    !! $code.subst: :g, ‘␤’, “\n”
}

multi method filter($response where (.encode.elems > MESSAGE-LIMIT
                                        or ?.?additional-files
                                        or (!~$_ and $_ ~~ ProperStr))) {
    # Here $response is a Str with a lot of stuff mixed in (possibly)
    my $description = ‘Whateverable’;
    my $text = colorstrip $response.?long-str // ~$response;
    my %files;
    %files<result> = $text if $text;
    %files.push: $_ with $response.?additional-files;

    if $response ~~ Reply {
        $description = $response.msg.server.current-nick;
        %files<query> = $_ with $response.?msg.text;
    }
    my $url = self.upload: %files, public => !%*ENV<DEBUGGABLE>, :$description;
    $url = $response.link-msg()($url) if $response ~~ PrettyLink;
    $url
}

multi method filter($text is copy) {
    ansi-to-irc($text).trans:
        “\n” => ‘␤’,
        3.chr => 3.chr, 0xF.chr => 0xF.chr, # keep these for IRC colors
        |((^32)».chr Z=> (0x2400..*).map(*.chr)), # convert all unreadable ASCII crap
        127.chr => ‘␡’, /<:Cc>/ => ‘␦’
}

method upload(%files is copy, :$description = ‘’, Bool :$public = True) {
    if %*ENV<TESTABLE> {
        my $gists-path = “{BUILDS-LOCATION}/tist”;
        rmtree $gists-path if $gists-path.IO ~~ :d;
        mkdir $gists-path;
        spurt “$gists-path/{.key}”, .value for %files;
        return ‘https://whatever.able/fakeupload’;
    }

    state $config = from-json slurp CONFIG;
    %files = %files.pairs.map: { .key => %( ‘content’ => .value ) }; # github format

    my $gist = Pastebin::Gist.new(token => $config<access_token>);
    return $gist.paste: %files, desc => $description, public => $public
}

method selfrun($nick is copy, @alias?) {
    $nick ~= ‘test’ if %*ENV<DEBUGGABLE>;
    .run with IRC::Client.new(
        :$nick
        :userreal($nick.tc)
        :username($nick.substr(0, 3) ~ ‘-able’)
        :password(?%*ENV<TESTABLE> ?? ‘’ !! from-json(slurp CONFIG)<irc-login irc-password>.join(‘:’))
        :@alias
        :host(%*ENV<TESTABLE> ?? ‘127.0.0.1’ !! ‘wilhelm.freenode.net’)
        :channels(%*ENV<DEBUGGABLE> ?? <#whateverable> !! <#perl6 #perl6-dev #whateverable #zofbot #moarvm>)
        :debug(?%*ENV<DEBUGGABLE>)
        :plugins(self)
        :filters( -> |c { self.filter(|c) } )
    )
}

# vim: expandtab shiftwidth=4 ft=perl6

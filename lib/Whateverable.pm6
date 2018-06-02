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

our $RAKUDO = (%*ENV<TESTABLE> // ‘’).contains(‘rakudo-mock’)
              ?? ‘./t/data/rakudo’.IO.absolute
              !! ‘./data/rakudo-moar’.IO.absolute;
constant MOARVM = ‘./data/moarvm’.IO.absolute;
constant SOURCE = ‘https://github.com/perl6/whateverable’;
constant WIKI   = ‘https://github.com/perl6/whateverable/wiki/’;
constant WORKING-DIRECTORY = ‘.’.IO.absolute; # TODO not supported yet
constant ARCHIVES-LOCATION = “{WORKING-DIRECTORY}/data/builds”.IO.absolute;
constant BUILDS-LOCATION   = ‘/tmp/whateverable/’.IO.absolute;

constant MESSAGE-LIMIT is export = 260;
constant COMMITS-LIMIT = 500;
our $GIST-LIMIT = 10_000;
constant $CAVE    = ‘#whateverable’;
constant $PARENTS = ‘AlexDaniel’, ‘MasterDuke’;

our $RAKUDO-REPO = ‘https://github.com/rakudo/rakudo’;
our $CONFIG;
sub ensure-config is export { $CONFIG //= from-json slurp; }

constant Message = IRC::Client::Message;

unit role Whateverable[:$default-timeout = 10] does IRC::Client::Plugin does Helpful;

my $default-stdin = slurp ‘stdin’;

my role Enough { } # to prevent recursion in exception handling

method TWEAK {
    # wrap around everything to catch exceptions
    once { # per class
        self.^lookup(‘irc-to-me’).wrap: sub ($self, $msg) {
            return if $msg.channel ne $CAVE and $msg.args[1].starts-with: ‘what:’;
            # ↑ ideally this check shouldn't be here, but it's much harder otherwise

            LEAVE sleep 0.02; # https://github.com/perl6/whateverable/issues/163
            try {
                my $result = callsame;
                return without $result;
                return $result but Reply($msg) if $result !~~ Promise;
                return start sub {
                    try return (await $result) but Reply($msg);
                    $self.handle-exception: $!, $msg
                }()
            }
            $self.handle-exception: $!, $msg
        };

        self.^lookup(‘filter’).wrap: sub ($self, $response) {
            my &filter = nextcallee;
            try { return filter $self, $response }
            return ‘Ow! Where's a camcorder when ya need one?’ if $response ~~ Enough;
            try { return filter $self, $self.handle-exception($!, $response.?msg) }
            ‘Sorry kid, that's not my department.’
        };
    }
    # TODO roles should not have TWEAK method
}

method handle-exception($exception, $msg?) is export {
    CATCH { # exception handling is too fat, so let's do this also…
        .note;
        return ‘Exception was thrown while I was trying to handle another exception…’
             ~ ‘ What are they gonna do to me, Sarge? What are they gonna do⁈’
    }
    if $exception ~~ Whateverable::X::HandleableAdHoc { # oh, it's OK!
        return $exception.message but Reply($_) with $msg;
        return $exception.message
    }

    note $exception;
    given $msg {
        # TODO handle other types
        when IRC::Client::Message::Privmsg::Channel {
            if .channel ne $CAVE {
                .irc.send-cmd: ‘PRIVMSG’, $CAVE, “I'm acting stupid on {.channel}. Help me.”,
                               :server(.server), :prefix($PARENTS.join(‘, ’) ~ ‘: ’)
            }
        }
        default {
            .irc.send-cmd: ‘PRIVMSG’, $CAVE, ‘Unhandled exception somewhere!’,
                           :server(.server), :prefix($PARENTS.join(‘, ’) ~ ‘: ’);
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
    if $msg !~~ IRC::Client::Message::Privmsg::Channel {
        $msg.irc.send-cmd: ‘PRIVMSG’, $CAVE, $return but Enough,
                           :server($msg.server), :prefix($PARENTS.join(‘, ’) ~ ‘: ’);
        return
    }
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
    $default-stdin = slurp ‘stdin’;
    ‘STDIN is reset to the default value’
}

multi method irc-to-me(Message $msg where .text ~~ /:i^ [stdin] [‘ ’|‘=’] $<stdin>=.* $/) {
    my $file = self.process-code: ~$<stdin>, $msg;
    $default-stdin = $file.slurp;
    unlink $file;
    “STDIN is set to «{shorten $default-stdin, 200}»” # TODO is 200 a good limit
}

multi method irc-to-me(Message $    where .text ~~ /:i^ [source|url] ‘?’? \s* $/ --> SOURCE) {}
multi method irc-to-me(Message $    where .text ~~ /:i^ wiki ‘?’? \s* $/) { self.get-wiki-link }
multi method irc-to-me(Message $msg where .text ~~ /:i^ [help|usage] ‘?’? \s* $/) {
    self.help($msg) ~ “ # See wiki for more examples: {self.get-wiki-link}”
}
multi method irc-to-me(Message $msg where .text ~~ /:i^ uptime \s* $/) {
    use nqp;
    use Telemetry;
    (denominate now - $*INIT-INSTANT) ~ ‘, ’
    ~ T<max-rss>.fmt(‘%.2f’) ÷ 1024 ~ ‘MiB maxrss. ’
    ~ (with nqp::getcomp("perl6") {
        “This is {.implementation} version {.config<version>} ”
        ~ “built on {.backend.version_string} ”
        ~ “implementing {.language_name} {.language_version}.”
     })
}
multi method irc-notice-me( $ --> Nil)                             {} # Issue #321
multi method irc-privmsg-me($ --> ‘Sorry, it is too private here’) {} # TODO issue #16
multi method irc-to-me($) {
    ‘I cannot recognize this command. See wiki for some examples: ’ ~ self.get-wiki-link
}

sub I'm-alive is export {
    return if %*ENV<TESTABLE> or %*ENV<DEBUGGABLE>;
    use NativeCall;
    sub sd_notify(int32, str --> int32) is native(‘systemd’) {*};
    sd_notify 0, ‘WATCHDOG=1’; # this may be called too often, see TODO below
}

multi method irc-all($) {
    # TODO https://github.com/zoffixznet/perl6-IRC-Client/issues/50
    I'm-alive;
    $.NEXT
}


method get-wiki-link { WIKI ~ self.^name }

method get-short-commit($original-commit) { # TODO not an actual solution tbh
    $original-commit ~~ /^ <xdigit> ** 7..40 $/
    ?? $original-commit.substr(0, 7)
    !! $original-commit
}

# TODO $default-timeout is VNNull when working in non-OOP style. Rakudobug it?
sub get-output(*@run-args, :$timeout = $default-timeout || 10,
               :$stdin, :$ENV, :$cwd = $*CWD, :$chomp = True) is export {
    my $proc = Proc::Async.new: |@run-args;

    my $fh-stdin;
    LEAVE .close with $fh-stdin;
    my $temp-file;
    LEAVE unlink $_ with $temp-file;
    with $stdin {
        if $stdin ~~ IO::Path {
            $fh-stdin = $stdin.open
        } elsif $stdin ~~ IO::Handle {
            $fh-stdin = $stdin
        } else {
            $temp-file = write-code $stdin;
            $fh-stdin = $temp-file.IO.open
        }
        $proc.bind-stdin: $fh-stdin
    }

    my @chunks;
    my $result;
    my $s-start = now;
    my $s-end;
    react {
        whenever $proc.stdout { @chunks.push: $_ }; # RT #131763
        whenever $proc.stderr { @chunks.push: $_ };
        whenever Promise.in($timeout) {
            $proc.kill; # TODO sends HUP, but should kill the process tree instead
            @chunks.push: “«timed out after $timeout seconds»”
        }
        whenever $proc.start: :$ENV, :$cwd { #: scheduler => BEGIN ThreadPoolScheduler.new { # TODO do we need to set scheduler?
            $result = $_;
            $s-end = now;
            done
        }
    }
    my $output = @chunks.join;
    %(
        output    => $chomp ?? $output.chomp !! $output,
        exit-code => $result.exitcode,
        signal    => $result.signal,
        time      => $s-end - $s-start,
    )
}

sub perl6-grep($stdin, $regex is copy, :$timeout = 180, :$complex = False, :$hack = 0) is export {
    my $full-commit = to-full-commit ‘HEAD’ ~ (‘^’ x $hack);
    die “No build for $full-commit. Oops!” unless build-exists $full-commit;
    $regex = “m⦑ $regex ⦒”;
    # TODO can we do something smarter?
    my $sep   = $complex ?? ｢“\0\0”｣ !! ｢“\0”｣;
    my $magic = “INIT \$*ARGFILES.nl-in = $sep; INIT \$*OUT.nl-out = $sep;”
              ~ ｢use nqp;｣
              ~ ｢ next unless｣
              ~ ($complex ?? ｢ nqp::substr($_, 0, nqp::index($_, “\0”)) ~~｣ !! ‘’) ~ “\n”
              ~ $regex ~ “;\n”
              ~ ｢last if $++ > ｣ ~ $GIST-LIMIT;
    my $file = write-code $magic;
    LEAVE unlink $_ with $file;
    my $result = run-snippet $full-commit, $file, :$timeout, :$stdin, args => (‘-np’,);
    my $output = $result<output>;
    # numbers less than zero indicate other weird failures ↓
    grumble “Something went wrong ($output)” if $result<signal> < 0;

    $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
    $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0;
    grumble $output if $result<exit-code> ≠ 0 or $result<signal> ≠ 0;
    my @elems = $output.split: ($complex ?? “\0\0” !! “\0”), :skip-empty;
    if @elems > $GIST-LIMIT {
        grumble “Cowardly refusing to gist more than $GIST-LIMIT lines”
    }
    @elems
}

sub fetch-build($full-commit-hash, :$backend!) {
    my $done;
    if %*ENV<TESTABLE> { # keep asking for more time
        $done = Promise.new;
        start react {
            whenever $done { done }
            whenever Supply.interval: 0.5 { test-delay }
        }
    }
    LEAVE { $done.keep } if $done.defined && %*ENV<TESTABLE>;

    my $ua = HTTP::UserAgent.new;
    $ua.timeout = 10;

    my $arch = $*KERNEL.name ~ ‘-’ ~ $*KERNEL.hardware;
    my $link = “{$CONFIG<mothership>}/$full-commit-hash?type=$backend&arch=$arch”;
    note “Attempting to fetch $full-commit-hash…”;

    my $response = $ua.get: :bin, $link;
    return unless $response.is-success;

    my $disposition = $response.header.field(‘Content-Disposition’).values[0];
    return unless $disposition ~~ /‘filename=’\s*(<.xdigit>+[‘.zst’|‘.lrz’])/;

    my $location = ARCHIVES-LOCATION.IO.add: $backend;
    my $archive  = $location.add: ~$0;
    spurt $archive, $response.content, :bin;

    if $archive.ends-with: ‘.lrz’ { # populate symlinks
        my $proc = run :out, :bin, <lrzip -dqo - -->, $archive;
        my $list = run :in($proc.out), :out, <tar --list --absolute-names>;
        my @builds = gather for $list.out.lines { # TODO assumes paths without newlines, dumb but I don't see another way
            take ~$0 if /^‘/tmp/whateverable/’$backend‘/’(<.xdigit>+)‘/’/;
        }
        for @builds.unique {
            my $symlink = $location.add: $_;
            $symlink.unlink if $symlink.e; # remove existing (just in case)
            $archive.IO.symlink: $symlink;
        }
    }

    return $archive
}

sub build-exists($full-commit-hash,
                 :$backend=‘rakudo-moar’,
                 :$force-local=False) is export {
    my $archive     = “{ARCHIVES-LOCATION}/$backend/$full-commit-hash.zst”.IO;
    my $archive-lts = “{ARCHIVES-LOCATION}/$backend/$full-commit-hash”.IO;
    # ↑ long-term storage (symlink to a large archive)

    my $answer = ($archive, $archive-lts).any.e.so;
    if !$force-local && !$answer && $CONFIG<mothership> {
        return so fetch-build $full-commit-hash, :$backend
    }
    $answer
}

method get-similar($tag-or-hash, @other?, :$repo=$RAKUDO) {
    my @options = @other;
    my @tags = get-output(cwd => $repo, ‘git’, ‘tag’,
                          ‘--format=%(*objectname)/%(objectname)/%(refname:strip=2)’,
                          ‘--sort=-taggerdate’)<output>.lines
                          .map(*.split(‘/’))
                          .grep({ build-exists .[0] || .[1],
                                               :force-local })
                          .map(*[2]);

    my $cutoff = $tag-or-hash.chars max 7;
    my @commits = get-output(cwd => $repo, ‘git’, ‘rev-list’,
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

#| Asks the test suite to delay the test failure (for 0.5s)
sub test-delay {
    use NativeCall;
    sub kill(int32, int32) is native {*};
    sub getppid(--> int32) is native {*};
    my $sig-compat = SIGUSR1;
    # ↓ Fragile platform-specific hack
    $sig-compat = 10 if $*PERL.compiler.version ≤ v2018.05;
    kill getppid, +$sig-compat; # SIGUSR1
}

sub run-smth($full-commit-hash, $code, :$backend=‘rakudo-moar’) is export {
    my $build-prepath =   “{BUILDS-LOCATION}/$backend”;
    my $build-path    =               “$build-prepath/$full-commit-hash”;
    my $archive-path  = “{ARCHIVES-LOCATION}/$backend/$full-commit-hash.zst”;
    my $archive-link  = “{ARCHIVES-LOCATION}/$backend/$full-commit-hash”;

    mkdir $build-prepath; # create all parent directories just in case
                          # (may be needed for isolated /tmp)
    # lock on the destination directory to make
    # sure that other bots will not get in our way.
    while run(:err(Nil), ‘mkdir’, ‘--’, $build-path).exitcode ≠ 0 {
        test-delay if %*ENV<TESTABLE>;
        note “$build-path is locked. Waiting…”;
        sleep 0.5 # should never happen if configured correctly (kinda)
    }
    if $archive-path.IO ~~ :e {
        if run :err(Nil), <pzstd --version> { # check that pzstd is available
            my $proc = run :out, :bin, <pzstd --decompress --quiet --stdout -->, $archive-path;
            run :in($proc.out), :bin, <tar --extract --absolute-names>;
        } else {
            die ‘zstd is not installed’ unless run :out(Nil), <unzstd --version>;
            # OK we are using zstd from the Mesozoic Era
            my $proc = run :out, :bin, <unzstd -qc -->, $archive-path;
            run :in($proc.out), :bin, <tar --extract --absolute-names>;
        }
    } else {
        die ‘lrzip is not installed’ unless run :err(Nil), <lrzip --version>; # check that lrzip is available
        my $proc = run :out, :bin, <lrzip --decompress --quiet --outfile - -->, $archive-link;
        run :in($proc.out), :bin, <tar --extract --absolute-names -->, $build-path;
    }

    my $return = $code($build-path); # basically, we wrap around $code
    rmtree $build-path;
    $return
}

# TODO $default-timeout is VNNull when working in non-OOP style. Rakudobug it?
sub run-snippet($full-commit-hash, $file, :$backend=‘rakudo-moar’, :@args=Empty,
                :$timeout=$default-timeout||10, :$stdin=$default-stdin, :$ENV) is export {
    run-smth :$backend, $full-commit-hash, -> $path {
        my $binary-path = $path.IO.add: ‘bin/perl6’;
        my %tweaked-env = $ENV // %*ENV;
        %tweaked-env<PATH> = join ‘:’, $binary-path.parent, (%tweaked-env<PATH> // Empty);
        %tweaked-env<PERL6LIB> = ‘sandbox/lib’;
        $binary-path.IO !~~ :e
        ?? %(output => ‘Commit exists, but a perl6 executable could not be built for it’,
             exit-code => -1, signal => -1, time => -1,)
        !! get-output $binary-path, |@args,
                      ‘--’, $file, :$stdin, :$timeout, ENV => %tweaked-env, :!chomp
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
        my $result = get-output :cwd($repo), ‘git’, ‘rev-list’, ‘--reverse’,
                                “$<start>^..$<end>”; # TODO unfiltered input
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

method get-tags($date, :$repo=$RAKUDO, :$dups=False, :@default=(‘HEAD’,)) {
    my @tags = @default;
    my %seen;
    for get-output(cwd => $repo, <git tag -l>)<output>.lines.reverse -> $tag {
        next unless $tag ~~ /^(\d\d\d\d\.\d\d)[\.\d\d?]?$/;
        next if Date.new($date) after Date.new($0.trans(‘.’=>‘-’)~‘-20’);
        next if $dups.not && %seen{~$0}++;
        @tags.push(~$tag)
    }
    @tags.reverse
}

sub to-full-commit($commit, :$short=False, :$repo=$RAKUDO) is export {
    return if run(:out(Nil), :err(Nil), :cwd($repo),
                  ‘git’, ‘rev-parse’, ‘--verify’, $commit).exitcode ≠ 0; # make sure that $commit is valid

    my $result = get-output cwd => $repo,
                            |(‘git’, ‘rev-list’, ‘-1’, # use rev-list to handle tags
                              ($short ?? ‘--abbrev-commit’ !! Empty), $commit);

    return if     $result<exit-code> ≠ 0;
    return unless $result<output>;
    $result<output>
}

sub write-code($code) is export {
    my ($filename, $filehandle) = tempfile :!unlink;
    $filehandle.print: $code;
    $filehandle.close;
    $filename.IO
}

sub process-gist($url, $msg) is export {
    return unless $url ~~
      /^ ‘https://gist.github.com/’<[a..zA..Z-]>+‘/’(<.xdigit>**32) $/;

    my $gist-id = ~$0;
    my $api-url = ‘https://api.github.com/gists/’ ~ $gist-id;

    my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
    my $response;
    try {
        $response = $ua.get: $api-url;
        CATCH {
            grumble “Cannot fetch data from GitHub API ({.message})”
        }
    }
    if not $response.is-success {
        grumble ‘Cannot fetch data from GitHub API’
                ~ “ (HTTP status line is {$response.status-line})”
    }

    my %scores; # used to determine the main file to execute

    my %data = from-json $response.decoded-content;
    grumble ‘Refusing to handle truncated gist’ if %data<truncated>;

    sub path($filename) { “sandbox/$filename”.IO }

    for %data<files>.values {
        grumble ‘Invalid filename returned’ if .<filename>.contains: ‘/’|“\0”;

        my $score = 0; # for heuristics
        $score += 50 if .<language> && .<language> eq ‘Perl 6’;
        $score -= 20 if .<filename>.ends-with: ‘.pm6’;
        $score += 40 if !.<language> && .<content>.contains: ‘ MAIN’;

        my IO $path = path .<filename>;
        if .<size> ≥ 10_000_000 {
            $score -= 300;
            grumble ‘Refusing to handle files larger that 10 MB’;
        }
        if .<truncated> {
            $score -= 100;
            grumble ‘Can't handle truncated files yet’; # TODO?
        } else {
            spurt $path, .<content>;
        }
        %scores.push: .<filename> => $score
    }

    my $main-file = %scores.max(*.value).key;
    if $msg and %scores > 1 {
        $msg.reply: “Using file “$main-file” as a main file, other files are placed in “sandbox/””
    }
    path $main-file;
}

sub process-url($url, $msg) is export {
    my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
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
                ~ “ (HTTP status line is {$response.status-line})”
    }
    if not $response.content-type.contains: ‘text/plain’ | ‘perl’ {
        grumble “It looks like a URL, but mime type is ‘{$response.content-type}’”
                ~ ‘ while I was expecting something with ‘text/plain’ or ‘perl’’
                ~ ‘ in it. I can only understand raw links, sorry.’
    }

    my $body = $response.decoded-content;
    .reply: ‘Successfully fetched the code from the provided URL’ with $msg;
    sleep 0.02; # https://github.com/perl6/whateverable/issues/163
    $body
}

method process-code($code is copy, $msg) {
    $code ~~ m{^ ( ‘http’ s? ‘://’ \S+ ) }
    ?? process-gist(~$0, $msg) // write-code process-url(~$0, $msg)
    !! write-code $code.subst: :g, ‘␤’, “\n”
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
        %files<query> = $_ with $response.?msg.?text;
        %files<query>:delete unless %files<query>;
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
        my $nick = $.irc.servers.values[0].current-nick;
        my $gists-path = “{BUILDS-LOCATION}/tist/$nick”;
        rmtree $gists-path if $gists-path.IO ~~ :d;
        mkdir $gists-path;
        spurt “$gists-path/{.key}”, .value for %files;
        return ‘https://whatever.able/fakeupload’;
    }

    %files = %files.pairs.map: { .key => %( ‘content’ => .value ) }; # github format

    my $gist = Pastebin::Gist.new(token => $CONFIG<github><access_token> || Nil);
    return $gist.paste: %files, desc => $description, public => $public
}

method selfrun($nick is copy, @alias?) {
    note “Bot pid: $*PID” if %*ENV<TESTABLE>;

    ensure-config;

    use Whateverable::Builds;
    ensure-cloned-repos;

    $nick ~= ‘test’ if %*ENV<DEBUGGABLE>;
    .run with IRC::Client.new(
        :$nick
        :userreal($nick.tc)
        :username($nick.substr(0, 3) ~ ‘-able’)
        :password(?%*ENV<TESTABLE> ?? ‘’ !! $CONFIG<irc><login password>.join: ‘:’)
        :@alias
        # IPv4 address of chat.freenode.net is hardcoded so that we can double the limit ↓
        :host(%*ENV<TESTABLE> ?? ‘127.0.0.1’ !! (‘chat.freenode.net’, ‘185.30.166.38’).pick)
        :port(%*ENV<TESTABLE> ?? %*ENV<TESTABLE_PORT> !! 6667)
        :channels(%*ENV<DEBUGGABLE>
                  ?? ‘#whateverable’
                  !! %*ENV<TESTABLE>
                     ?? “#whateverable_$nick”
                     !! (|<#perl6 #perl6-dev #zofbot #moarvm>, $CAVE) )
        :debug(?%*ENV<DEBUGGABLE>)
        :plugins(self)
        :filters( -> |c { self.filter(|c) } )
    )
}

# TODO move somewhere
# TODO commit unused
sub subprocess-commit($commit, $filename, $full-commit, :%ENV) is export {
    return ‘No build for this commit’ unless build-exists $full-commit;

    $_ = run-snippet $full-commit, $filename, :%ENV; # actually run the code
    # numbers less than zero indicate other weird failures ↓
    return “Cannot test this commit ($_<output>)” if .<signal> < 0;
    my $output = .<output>;
    $output ~= “ «exit code = $_<exit-code>»” if .<exit-code> ≠ 0;
    $output ~= “ «exit signal = {Signal($_<signal>)} ($_<signal>)»” if .<signal> ≠ 0;
    $output
}

# vim: expandtab shiftwidth=4 ft=perl6

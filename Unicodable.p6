#!/usr/bin/env perl6
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

use lib ‘.’;
use Misc;
use Uniprops;
use Whateverable;

use IRC::Client;

unit class Unicodable does Whateverable;

constant MESSAGE-LIMIT = 3;

method TWEAK {
    self.timeout = 30;
}

method help($msg) {
    ‘Just type any unicode character or part of a character name. Alternatively, you can also provide a code snippet.’
}

multi method irc-to-me($msg) {
    if $msg.args[1] ~~ / ^ ‘.u’ \s / {
        my $update-promise = Promise.new;
        $!update-promise-channel.send: $update-promise;
        $msg.irc.send-cmd: ‘NAMES’, $msg.channel;
        start {
            await Promise.anyof: $update-promise, Promise.in(4);
            $!users-lock.protect: {
                return if any %!users{$msg.channel}<yoleaux yoleaux2>:exists
            }
            my $value = self.process: $msg, $msg.text;
            $msg.reply: $_ but Reply($msg) with $value
        }
        return
    } elsif $msg.args[1].starts-with: ‘propdump:’ | ‘unidump:’ {
        my $value = self.propdump: $msg, $msg.text;
        return without $value;
        return $value but Reply($msg)
    } else {
        my $value = self.process: $msg, $msg.text;
        return without $value;
        return $value but Reply($msg)
    }
}

multi method irc-privmsg-channel($msg where .args[1] ~~ / ^ ‘.u’ \s* (.*)/) {
    $msg.text = ~$0;
    self.irc-to-me($msg)
}

method get-description($ord) {
    my $char;
    try {
        $char = $ord.chr;
        CATCH { default { return sprintf “U+%04X (invalid codepoint)”, $ord } }
    }
    $char = ‘◌’ ~ $ord.chr if $ord.uniprop.starts-with: ‘M’; # TODO ask samcv
    try {
        $char.encode;
        CATCH { default { $char = ‘unencodable character’ } }
    }
    $char = ‘control character’ if $ord.uniprop eq ‘Cc’;
    sprintf “U+%04X %s [%s] (%s)”, $ord, $ord.uniname, $ord.uniprop, $char
}

method process($msg, $query is copy) {
    my $old-dir = $*CWD;

    my ($succeeded, $code-response) = self.process-code: $query, $msg;
    return $code-response unless $succeeded;
    $query = $code-response;
    my $filename;

    my @all;

    if $query ~~ m:ignoremark/^ :i \s*
                             [
                                 [ | ‘u’ (.) <?{ $0[*-1].Str.uniname.match: /PLUS.*SIGN/ }>
                                   | [ <:Nd> & <:Numeric_Value(0)> ] ‘x’ # TODO is it fixed now?
                                 ]
                                 $<digit>=<:HexDigit>+
                             ]+ %% \s+
                             $/ {
        for $<digit> {
            my $char-desc = self.get-description: parse-base ~$_, 16;
            @all.push: $char-desc;
            $msg.reply: $char-desc if @all [<] MESSAGE-LIMIT
        }
    } elsif $query ~~ /^ <+[a..zA..Z] +[0..9] +[\-\ ]>+ $/ {
        my @words;
        my @props;
        for $query.words {
            if /^ <[A..Z]> <[a..z]> $/ {
                @props.push: $_
            } else {
                @words.push: .uc
            }
        }
        # ↓ do not touch these three lines
        my $sieve = 0..0x10FFFF;
        for @words -> $word { $sieve .= grep({uniname($_).contains($word)}) };
        for @props -> $prop { $sieve .= grep({uniprop($_) eq $prop}) };

        for @$sieve {
            my $char-desc = self.get-description: $_;
            @all.push: $char-desc;
            $msg.reply: $char-desc if @all [<] MESSAGE-LIMIT
        }
    } elsif $query ~~ /^ ‘/’ / {
        return ‘Regexes are not supported yet, sorry! Try code blocks instead’
    } elsif $query ~~ /^ ‘{’ / {
        my $full-commit = self.to-full-commit: ‘HEAD’;
        my $output = ‘’;
        $filename = self.write-code: “say join “\c[31]”, (0..0x10FFFF).grep:\n” ~ $query;
        if not self.build-exists: $full-commit {
            $output = ‘No build for the last commit. Oops!’;
            self.beg-for-help: $msg
        } else { # actually run the code
            my $result = self.run-snippet: $full-commit, $filename;
            $output = $result<output>;
            if $result<signal> < 0 { # numbers less than zero indicate other weird failures
                $output = “Something went wrong ($output)”;
                return $output
            } else {
                $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
                $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0;
                return $output if $result<exit-code> ≠ 0 or $result<signal> ≠ 0
            }
        }
        if $output {
            for $output.split: “\c[31]” {
                try {
                    my $char-desc = self.get-description: +$_;
                    @all.push: $char-desc;
                    $msg.reply: $char-desc if @all [<] MESSAGE-LIMIT;
                    CATCH {
                        .say;
                        self.beg-for-help($msg);
                        return ‘Oops, something went wrong!’
                    }
                }
            }
        }
    } else {
        for $query.comb».ords.flat {
            my $char-desc = self.get-description: $_;
            @all.push: $char-desc;
            if @all [<] MESSAGE-LIMIT {
                sleep 0.05 if @all > 1; # let's try to keep it in order
                $msg.reply: $char-desc
            }
        }
    }
    return @all[*-1] if @all == MESSAGE-LIMIT;
    if @all > MESSAGE-LIMIT {
        my $link-msg = { “{+@all} characters in total: $_” };
        return (‘’ but ProperStr(@all.join: “\n”)) but PrettyLink($link-msg)
    }
    return ‘Found nothing!’ if not @all;
    return

    LEAVE {
        chdir $old-dir;
        unlink $filename if defined $filename and $filename.chars > 0
    }
}

method propdump($msg, $query) {
    my $answer = ‘’;
    my @query = $query.comb>>.ords.flat;
    for @prop-table -> $category {
        $answer ~= sprintf “\n### %s\n”, $category.key;
        $answer ~= sprintf “| %-55s |”, ‘Property names’;
        $answer ~= .fmt: “ %-25s |” for @query.map: -> $char {“Value: {chr $char}”};
        $answer ~= “\n”;
        $answer ~= “|{‘-’ x 57}|”;
        $answer ~= “{‘-’ x 27}|” x @query;
        $answer ~= “\n”;
        for $category.value -> $cat {
            my @props = @query.map: *.uniprop($cat[0]);
            my $bold = ([eq] @props) ⁇ ｢｣ ‼ ｢**｣;
            $answer ~= sprintf(｢| %1$s%2$s%1$s |｣, $bold, $cat.join(‘, ’)).fmt: “%-55s”;
            $answer ~= .fmt: “ %-25s |” for @props;
            $answer ~= “\n”;
        }
    }
    ‘’ but FileStore({ ‘result.md’ => $answer })
}

# ↓ Here we will try to keep track of users on the channel.
#   This is a temporary solution. See this bug report:
#   * https://github.com/zoffixznet/perl6-IRC-Client/issues/29
has %!users;
has $!users-lock = Lock.new;
has $!update-promise-channel = Channel.new;
has %!temp-users;

method irc-n353($e) {
    my $channel = $e.args[2];
    # Try to filter out privileges ↓
    my @nicks = $e.args[3].words.map: { m/ (<[\w \[ \] \ ^ { } | ` -]>+) $/[0].Str };
    %!temp-users{$channel} //= SetHash.new;
    %!temp-users{$channel}{@nicks} = True xx @nicks
}

method irc-n366($e) {
    my $channel = $e.args[1];
    $!users-lock.protect: {
        %!users{$channel} = %!temp-users{$channel};
        %!temp-users{$channel}:delete
    };
    loop {
        my $promise = $!update-promise-channel.poll;
        last without $promise;
        try { $promise.keep } # could be already kept
    }
}

Unicodable.new.selfrun: ‘unicodable6’, [/u6?/, /uni6?/, fuzzy-nick(‘unicodable6’, 3), ‘propdump’, ‘unidump’];

# vim: expandtab shiftwidth=4 ft=perl6

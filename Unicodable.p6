#!/usr/bin/env perl6
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

use lib ‘.’;
use Whateverable;

use IRC::Client;

unit class Unicodable is Whateverable;

constant MESSAGE-LIMIT = 3;

submethod TWEAK() {
    self.always-upload = True;
    self.timeout = 30;
}

method help($message) {
    “Just type any unicode character or part of a character name. Alternatively, you can also provide a code snippet or a regex”
};

multi method irc-to-me($message) {
    if $message.args[1] ~~ / ^ ‘.u’ \s / {
        my $update-promise = Promise.new;
        $!update-promise-channel.send: $update-promise;
        $message.irc.send-cmd: 'NAMES', $message.channel;
        start { # if this crashes it's not my fault
            await Promise.anyof($update-promise, Promise.in(4));
            $!users-lock.protect: {
                return if %!users{$message.channel}<yoleaux yoleaux2>;
            }
            my $value = self.process($message, $message.text);
            $message.reply: ResponseStr.new(:$value, :$message) if $value;
        }
        return
    } else {
        my $value = self.process($message, $message.text);
        return ResponseStr.new(:$value, :$message) if $value;
        return
    }
}

method get-description($ord) {
    my $char = $ord.chr;
    $char = ‘◌’ ~ $ord.chr if $char.uniprop.starts-with(‘M’);
    try {
        $char.encode;
        CATCH { default { $char = ‘unencodable character’ } }
    }
    $char = ‘control character’ if uniprop($ord) eq ‘Cc’;
    sprintf("U+%04X %s [%s] (%s)", $ord, uniname($ord), uniprop($ord), $char)
}

method process($message, $query is copy) {
    my $old-dir = $*CWD;

    my ($succeeded, $code-response) = self.process-code($query, $message);
    return $code-response unless $succeeded;
    $query = $code-response;
    my $filename;

    my @all;

    if $query ~~ /^ \s* [ [ (.) <?{ $0[*-1].Str.samemark(‘a’).fc eq ‘u’.fc  }>
                            (.) <?{ $1[*-1].Str.uniname.match(/PLUS.*SIGN/) }>
                            |
                            [ <:Nd> & <:Numeric_Value(0)> ]
                            (.) <?{ $0[*-1].Str.samemark(‘a’).fc eq ‘x’.fc  }>
                          ]
                          [$<digit>=<:HexDigit>+] ]+ %% \s+ $/ {
        for $<digit> {
            my $char-desc = self.get-description(parse-base(~$_, 16));
            @all.push: $char-desc;
            $message.reply: $char-desc if @all < MESSAGE-LIMIT; # >;
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
            my $char-desc = self.get-description($_);
            @all.push: $char-desc;
            $message.reply: $char-desc if @all < MESSAGE-LIMIT; # >;
        }
    } elsif $query ~~ /^ ‘/’ / {
        return ‘Regexes are not supported yet, sorry! Try code blocks instead’;
    } elsif $query ~~ /^ ‘{’ / {
        my $full-commit = self.to-full-commit(‘HEAD’);
        my $output = ‘’;
        $filename = self.write-code(“say join “\c[31]”, (0..0x10FFFF).grep:\n” ~ $query);
        if not self.build-exists($full-commit) {
            $output = ‘No build for the last commit. Oops!’;
        } else { # actually run the code
            ($output, my $exit, my $signal, my $time) = self.run-snippet($full-commit, $filename);
            if $signal < 0 { # numbers less than zero indicate other weird failures
                $output = “Something went wrong ($output)”;
                return $output;
            } else {
                $output ~= “ «exit code = $exit»” if $exit != 0;
                $output ~= “ «exit signal = {Signal($signal)} ($signal)»” if $signal != 0;
                return $output if $exit != 0 or $signal != 0;
            }
        }
        if $output {
            for $output.split(“\c[31]”) {
                try {
                    my $char-desc = self.get-description(+$_);
                    @all.push: $char-desc;
                    $message.reply: $char-desc if @all < MESSAGE-LIMIT; # >;
                    CATCH {
                        .say;
                        return ‘Oops, something went wrong!’;
                    }
                }
            }
        }
    } else {
        for $query.comb».ords.flat {
            my $char-desc = self.get-description($_);
            @all.push: $char-desc;
            $message.reply: $char-desc if @all < MESSAGE-LIMIT; # >;
        }
    }
    return @all[*-1] if @all == MESSAGE-LIMIT;
    return @all.join: “\n” if @all > MESSAGE-LIMIT;
    return ‘Found nothing!’ if not @all;
    return;

    LEAVE {
        chdir $old-dir;
        unlink $filename if $filename.defined and $filename.chars > 0;
    }
}

# ↓ Here we will try to keep track of users on the channel.
#   This is a temporary solution. See this bug report:
#   * https://github.com/zoffixznet/perl6-IRC-Client/issues/29
has %!users;
has $!users-lock = Lock.new;
has $!update-promise-channel = Channel.new;
has %!temp-users;

method irc-n353 ($e) {
    my $channel = $e.args[2];
    # Try to filter out privileges ↓
    my @nicks = $e.args[3].words.map: { m/ (<[\w \[ \] \ ^ { } | ` -]>+) $/[0].Str };
    %!temp-users{$channel} //= SetHash.new;
    %!temp-users{$channel}{@nicks} = True xx @nicks;
}

method irc-n366 ($e) {
    my $channel = $e.args[1];
    $!users-lock.protect: {
        %!users{$channel} = %!temp-users{$channel};
        %!temp-users{$channel}:delete;
    };
    loop {
        my $promise = $!update-promise-channel.poll;
        last if not defined $promise;
        try { $promise.keep } # could be already kept
    }
}

Unicodable.new.selfrun(‘unicodable6’, [/u6?/, /uni6?/, fuzzy-nick(‘unicodable6’, 3) ]);

# vim: expandtab shiftwidth=4 ft=perl6

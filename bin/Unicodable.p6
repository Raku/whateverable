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

use Whateverable;
use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Processing;
use Whateverable::Replaceable;
use Whateverable::Running;
use Whateverable::Uniprops;

use IRC::Client;

unit class Unicodable does Whateverable does Whateverable::Replaceable;

constant MESSAGE-LIMIT = 3;
constant $LIMIT = 5_000;
constant $PREVIEW-LIMIT = 50;

method help($msg) {
    ‘Just type any Unicode character or part of a character name. Alternatively, you can also provide a code snippet.’
}

multi method irc-to-me($msg) {
    if $msg.args[1].starts-with: ‘propdump:’ | ‘unidump:’ {
        return self.propdump: $msg, $msg.text
    }
    return self.process: $msg, $msg.text if $msg.args[1] !~~ /^ ‘.u’ \s /;
    self.make-believe: $msg, <yoleaux yoleaux2>, {
        self.process: $msg, $msg.text
    }
}

multi method irc-privmsg-channel($msg where .args[1] ~~ /^ ‘.u’ \s (.*) /) {
    $msg.text = ~$0;
    self.irc-to-me: $msg
}

multi method codepointify(Int $ord ) { $ord.fmt: ‘U+%04X’ }
multi method codepointify(Str $char) { $char.ords».fmt(‘U+%04X’).join: ‘, ’ }

method sanify($ord) {
    my $char;
    try {
        $char = $ord.chr;
        CATCH { return “{self.codepointify($ord)} (invalid codepoint)” }
    }
    try {
        $char.encode;
        CATCH { return ‘unencodable character’ }
    }
    my $gcb = $ord.uniprop(‘Grapheme_Cluster_Break’);
    return “\c[NBSP]” ~ $char              if $gcb eq ‘Extend’ | ‘ZWJ’;
    return              $char ~ “\c[NBSP]” if $gcb eq ‘Prepend’;
    return ‘control character’             if $gcb eq ‘Control’ | ‘CR’ | ‘LF’;
    $char
}

method get-description($ord) {
    my $sane = self.sanify: $ord;
    return $sane if $sane.ends-with: ‘(invalid codepoint)’;
    sprintf “%s %s [%s] (%s)”,
            self.codepointify($ord), $ord.uniname,
            $ord.uniprop, $sane
}

method get-preview(@all) {
    return ‘’ if @all > $PREVIEW-LIMIT;
    return ‘’ if @all».uniprop(‘Grapheme_Cluster_Break’).any eq
                 ‘Control’ | ‘CR’ | ‘LF’ | ‘Extend’ | ‘Prepend’ | ‘ZWJ’;
    my $preview = @all».chr.join;
    return ‘’ if @all !~~ $preview.comb».ord; # round trip test
    “ ($preview)”
}

method compose-gist(@all) {
    my $gist = @all.map({self.get-description: $_}).join: “\n”;
    my $link-msg = { “{+@all} characters in total{self.get-preview: @all}: $_” };
    (‘’ but ProperStr($gist)) but PrettyLink($link-msg)
}

method from-numerics($query) {
    $query ~~ m:ignoremark/^
        :i \s*
        [
            [ | [｢\U｣ | ‘u’ (.) <?{ $0[*-1].Str.uniname.match: /PLUS.*SIGN/ }> ]
              | [ <:Nd> & <:Numeric_Value(0)> ] ‘x’ # TODO is it fixed now? … What exactly?
            ]
            $<digit>=<:HexDigit>+
        ]+ %% \s+
        $/;
    return () without $<digit>;
    $<digit>.map: { parse-base ~$_, 16 }
}

method process($msg, $query is copy) {
    my $file = process-code $query, $msg;
    LEAVE .unlink with $file;

    my $file-contents = $file.slurp;
    if $file-contents ne $query {
        $query = $file-contents # fetched from URL
    } elsif not $msg.args[1].match: /^ ‘.u’ \s / {
        $query = ~$0 if $msg.args[1] ~~ / <[,:]> \s (.*) / # preserve leading spaces
    }
    my @all;

    my @numerics = self.from-numerics: $query;
    if @numerics {
        for @numerics {
            @all.push: $_;
            $msg.reply: self.get-description: $_ if @all [<] MESSAGE-LIMIT
        }
    } elsif $query.trim-trailing ~~ /^ <+[a..zA..Z] +[0..9] +[\-\ ]>+ $ && .*? \S / {
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
            @all.push: $_;
            grumble “Cowardly refusing to gist more than $LIMIT lines” if @all > $LIMIT;
            $msg.reply: self.get-description: $_ if @all [<] MESSAGE-LIMIT
        }
    } elsif $query.starts-with: ‘/’ {
        grumble ‘Regexes are not supported yet, sorry! Try code blocks instead’
    } elsif $query.starts-with: ‘{’ {
        my $full-commit = to-full-commit ‘HEAD’;
        my $output = ‘’;
        my $file = write-code “say join “\c[31]”, (0..0x10FFFF).grep:\n” ~ $query;
        LEAVE unlink $_ with $file;

        die ‘No build for the last commit. Oops!’ unless build-exists $full-commit;

        # actually run the code
        my $result = run-snippet $full-commit, $file;
        $output = $result<output>;
        # numbers less than zero indicate other weird failures ↓
        grumble “Something went wrong ($output)” if $result<signal> < 0;

        $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
        $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0;
        return $output if $result<exit-code> ≠ 0 or $result<signal> ≠ 0;

        for $output.split: “\c[31]”, :skip-empty {
            @all.push: +$_;
            grumble “Cowardly refusing to gist more than $LIMIT lines” if @all > $LIMIT;
            $msg.reply: self.get-description: +$_ if @all [<] MESSAGE-LIMIT
        }
    } else {
        for $query.comb».ords.flat {
            @all.push: $_;
            grumble “Cowardly refusing to gist more than $LIMIT lines” if @all > $LIMIT;
            if @all [<] MESSAGE-LIMIT {
                sleep 0.05 if @all > 1; # let's try to keep it in order
                $msg.reply: self.get-description: $_
            }
        }
    }

    return self.get-description: @all[*-1] if @all == MESSAGE-LIMIT;
    return self.compose-gist:    @all      if @all >  MESSAGE-LIMIT;
    return ‘Found nothing!’            unless @all;
    return
}

method propdump($msg, $query) {
    my $answer = ‘’;
    my @numerics = self.from-numerics: $query;
    my @query = @numerics || $query.comb».ords.flat;
    my &escape = *.trans: (‘|’,) => (‘&#124;’,);
    for @prop-table -> $category {
        $answer ~= sprintf “\n### %s\n”, $category.key;
        $answer ~= sprintf ‘| %-55s |’, ‘Property names’;
        $answer ~= .fmt: ‘ %-25s |’ for @query.map: -> $char { “Value: {&escape(self.sanify: $char)}” };
        $answer ~= “\n”;
        $answer ~= “|{‘-’ x 57}|”;
        $answer ~= “{‘-’ x 27}|” x @query;
        $answer ~= “\n”;
        for $category.value -> $cat {
            my @props = @query.map: *.uniprop: $cat[0];
            my $bold = ([eq] @props) ?? ｢｣ !! ｢**｣;
            $answer ~= ($bold ~ $cat.join(‘, ’) ~ $bold).fmt: ‘| %-55s |’;
            $answer ~= &escape(.comb».ords.flat.map({self.sanify: $_}).join).fmt: ‘ %-25s |’ for @props;
            $answer ~= “\n”;
        }
    }
    ‘’ but FileStore({ ‘result.md’ => $answer })
}


my %*BOT-ENV = :30timeout;

Unicodable.new.selfrun: ‘unicodable6’, [/ u[ni]?6? <before ‘:’> /, ‘propdump’, ‘unidump’,
                                        fuzzy-nick(‘unicodable6’, 3)];

# vim: expandtab shiftwidth=4 ft=perl6

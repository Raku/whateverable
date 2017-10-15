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
use Misc;

use IRC::Client;
use JSON::Fast;

my $RESULT-DIR = ‘data/regressionable/’.IO;
my $CACHE-DIR  = ‘data/irc/’.IO;
my $LINK       = ‘https://irclog.perlgeek.de’;
my $CUTOFF     = 11631117; # 11631117 is ≈2015-12-01

my $IGNORE     = /:i «[rand|pick|roll|rm|shell|run|qx|qqx|slurp|spurt|nativecall]» /;
my @REVISIONS  = <2015.12 2016.06 2016.12 2017.06 f72be0f130cf>;

multi sub MAIN(‘populate’) {
    mkdir $RESULT-DIR;
    for $CACHE-DIR.dir(test => *.ends-with: ‘.cache’) {
        my $channel = .basename.subst(/ ^‘#’ /, ‘’).subst(/ ‘.cache’$ /, ‘’);
        for .split(“\0\0”) {
            my ($text, $id, $date) = .split: “\0”;
            next unless /^ [‘m’|‘r’|‘p6’]‘:’ /;
            $text .= subst: /.+? ‘:’ \s?/, ‘’;
            die ‘Empty message id’       unless  $id;
            die ‘Non-numeric message id’ unless +$id;
            my $snippet-path = $RESULT-DIR.add($id);
            next if $snippet-path.d; # already exists
            mkdir $snippet-path;
            spurt $snippet-path.add(‘snippet’), “$text\n”;
            spurt $snippet-path.add(‘link’), “$LINK/$channel/$date#i_$id\n”;
        }
    }
}

multi sub MAIN() {
    my @full-commits = @REVISIONS.map: &to-full-commit;
    for $RESULT-DIR.dir.grep(*.basename > $CUTOFF).pick(*) {
        my $status      = .add(‘status’);
        next if $status.e;
        my $snippet     = .add(‘snippet’);
        my $sneak-peek  = .add(‘sneak-peek’);
        my $code = $snippet.slurp.chomp;
        next if $code ~~ $IGNORE;
        I'm-alive;
        #say $code;
        #prompt ‘OK?’;

        my @output = do for @full-commits {
            subprocess-commit ‘’, $snippet.absolute, $_
        }
        if [eq] @output {
            spurt $status, “stable\n”;
            #say ‘it's fine’;
            next
        }
        my $peek = “$code\n\n”;
        @output .= map: { shorten $_, 800 };
        for @REVISIONS Z=> @output {
            $peek ~= “\n¦«{.key}»:\n{.value}\n”
        }
        spurt $status,      “unstable\n”;
        spurt $sneak-peek,  $peek;
        note “Processed {.basename}”;
        #say $peek;
        last if $++ > 50; # restart sometimes to free memory :(
    }
}

my $help = ‘Commands:
          (o)k        – the output is correct on HEAD
          ski(p)      – you don't know yet
          (i)nvalid   – the snippet is meaningless
          (f)uck      – go back if you fucked up’;

multi sub MAIN(‘play’) {
    say $help;

    say ‘’;
    say ‘Hold on…’;

    my @snippets = $RESULT-DIR.dir.grep(*.add(‘status’).e).map(+*.basename).sort().reverse;
    my @unstable;

    for @snippets {
        my $status = $RESULT-DIR.add($_).add(‘status’).slurp.chomp;
        @unstable.push: $_ if $status eq ‘unstable’;
    }
    say “{+@snippets} snippets tested, {+@unstable} are known to be unstable”;
    prompt ‘Press Enter to play’;

    loop (my $i = 0; $i < @unstable;) {
        $i += check @unstable[$i]
    }
}

sub check($id) {
    my $status-file = $RESULT-DIR.add($id).add(‘status’);
    my $status      = $status-file.slurp.chomp;
    my $sneak-peek  = $RESULT-DIR.add($id).add(‘sneak-peek’);
    my $link        = $RESULT-DIR.add($id).add(‘link’).slurp;
    say “---------------------------------------------------\n\n\n\n\n”;

    say “Code:”;

    run :in($*IN), :out($*OUT), ‘less’, ‘--RAW-CONTROL-CHARS’,
        ‘--quit-if-one-screen’, ‘--no-init’, ‘--’,
        $sneak-peek;

    say “\n”;
    say “Possible IRC discussion: $link\n”;

    given prompt ‘Your answer: ’ {
        when ‘o’ { spurt $status-file, “ok({@REVISIONS.tail})\n”; 1 }
        when ‘i’ { spurt $status-file, “invalid\n”;               1 }
        when ‘f’ { -1 }
        when /^‘p’ \s* (\d+)?/ { try +($0 // 1) // 0 }
        default  { say “I'm sorry Dave, I'm afraid I can't do that\n$help”;
                   prompt ‘Press Enter if you understand’;
                   0 }
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

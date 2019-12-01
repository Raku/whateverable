#!/usr/bin/env perl6

use Whateverable;
use Whateverable::Bits;
use Whateverable::Output;

unit class Sourceable does Whateverable;

method help($msg) {
    "Like this: sourceable6: Int, 'base'";
}

multi method irc-to-me($msg) {
    indir $*TMPDIR, sub {
        my $result = get-output($*EXECUTABLE.absolute, '-MCoreHackers::Sourcery', '-e', "put sourcery($msg.text())[1];");
        if $result<exit-code> == 0 {
            return "Sauce is at $result<output>";
        } else {
            return "No idea, boss";
        }
    }
}

my %*BOT-ENV;

Sourceable.new.selfrun: 'sourceable6', [ / sourceable6? <before ':'> /, fuzzy-nick('sourceable6', 2) ];

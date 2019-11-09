#!/usr/bin/env perl6

use Whateverable;
use Whateverable::Bits;

unit class Sourceable does Whateverable;

method help($msg) {
    "Like this s: Int, 'base'";
}

multi method irc-to-me($msg where /^ 's:' \s+ $<code>=.+/) {
    my $code = ~$<code>;
    is-safeish $code or return "Ehhh... I'm too scared to run that code.";

    indir $*TMPDIR, sub {
        my $p = run(
            :err,
            :out,  './perl6-m', '-MCoreHackers::Sourcery',
            '-e', qq:to/END/
                BEGIN \{
                    \%*ENV<SOURCERY_SETTING>
                    = {$*EXECUTABLE.parent.parent.parent.child('gen/moar/CORE.setting')};
                \};
                use CoreHackers::Sourcery;
                put sourcery( $code )[1];
            END
        );
        my $result = $p.out.slurp-rest;
        my $merge = $result ~ "\nERR: " ~ $p.err.slurp-rest;
        return "Something's wrong: $merge.subst("\n", '␤', :g)"
            unless $result ~~ /github/;

        return "Sauce is at $result";
    }
}

sub is-safeish ($code) {
    return if $code ~~ /<[;{]>/;
    return if $code.comb('(') != $code.comb(')');
    for <run shell qx EVAL> -> $danger {
        return if $code ~~ /«$danger»/
    }
    return True;
}

my %*BOT-ENV;

Sourceable.new.selfrun: 'sourceable6', [ / sourceable6? <before ':'> /, fuzzy-nick('sourceable6', 2) ];

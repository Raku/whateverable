#!/usr/bin/env perl6
use Whateverable;
use Misc;

unit class Nativecallable does Whateverable;

my $GPTrixie-BIN = ‘gptrixie’;

method help($msg) {
    “Like this {$msg.server.current-nick}: <some C definition>”;
}

sub run-gptrixie($header-file) {
    my %output = get-output $GPTrixie-BIN, ‘--all’, ‘--silent’, $header-file;
    if %output<output>.lines > 20 {
        return ‘’ but FileStore(%(‘Result.pm6’ => %output<output>))
    }
    my @pruned-output;
    @pruned-output = %output<output>.lines.grep: { $_ and not .starts-with: ‘#’ };
    if @pruned-output ≤ 10 {
        return (@pruned-output.map: {.subst(/\s+/, " ", :g)}).join: “\n”;
    }
    my $definitive-output //= %output<output>;
    ‘’ but FileStore(%(‘Result.pm6’ => $definitive-output))
}

multi method irc-to-me($msg where /^ \s* $<code>=.+ /) {
    my $code = self.process-code: $<code>, $msg;
    my $header-file = write-code “\n” ~ $code; # TODO “\n” is a workaround
    LEAVE unlink $_ with $header-file;
    run-gptrixie($header-file)
}


Nativecallable.new.selfrun: ‘nativecallable6’, [ / nativecall6? <before ‘:’> /,
                                                 fuzzy-nick(‘nativecallable6’, 2) ];

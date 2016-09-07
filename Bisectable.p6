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

use File::Temp;
use File::Directory::Tree;
use IRC::Client;

unit class Bisectable is Whateverable;

constant LINK          = ‘https://github.com/rakudo/rakudo/commit’;
constant BUILD-LOCK    = ‘./lock’.IO.absolute;

method help($message) {
    ~ “Like this: {$message.server.current-nick}”
    ~ ‘: good=2015.12 bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT128181’
}

method run-bisect($code-file, $compare-to?) {
    my $bisect-log = '';
    loop {
        my ($log, $exit-code) = self.test-commit($code-file, $compare-to);
        $bisect-log ~= $log;

        if $exit-code < 0 or $exit-code >= 128 {
            return ("bisect run failed: exit code $exit-code from '$code-file' is < 0 or >= 128", $exit-code);
        }

        given $exit-code {
            my ($output, $status);
            when 125  { run('git', 'bisect', 'skip') }
            when 1..* {
                ($output, $status) = self.get-output('git', 'bisect', 'bad');
                if $output ~~ /^^ \S+ ' is the first bad commit' / {
                    return ($bisect-log ~ $output, $status);
                }
            }
            default   {
                ($output, $status) = self.get-output('git', 'bisect', 'good');
                if $output ~~ /^^ \S+ ' is the first bad commit' / {
                    return ($bisect-log ~ $output, $status);
                }
            }
        }
    }
}

method test-commit($code-file, $compare-to?) {
    my ($current-commit,) = self.get-output('git', 'rev-parse', 'HEAD');
    my $log               = '';

    $log ~= "»»»»» Testing $current-commit\n";
    if not self.build-exists($current-commit) {
        $log ~= "»»»»» Build does not exist, skip this commit\n";
        $log ~= "»»»»» Final exit code: 125\n";
        return $log, 125 # skip non-existent builds
    }

    my ($output, $exit-code, $signal) = self.run-snippet($current-commit, $code-file);
    if $signal < 0 {
        $log ~= “»»»»» Cannot test this commit. Reason: $output\n”;
        $log ~= "»»»»» Final exit code: 125\n";
        return $log, 125 # skip failed builds
    }

    $log ~= "»»»»» Script output:\n";
    $log ~= $output;
    $log ~= "\n»»»»» Script exit code: $exit-code\n";

    # TODO bisect by signal (issue #14)

    # plain bisect
    unless $compare-to {
        $log ~= "»»»»» Plain bisect, using the same exit code\n";
        $log ~= "»»»»» Final exit code: $exit-code\n";
        return ($log, $exit-code);
    }

    # inverted exit code
    if $compare-to ~~ /^ \d+ $/ { # invert exit code
        $log ~= "»»»»» Inverted logic, comparing $exit-code to $compare-to\n";
        if $exit-code == $compare-to {
            $log ~= "»»»»» Final exit code: 0\n";
            return $log, 0;
        } else {
            my $final-exit-code = $exit-code == 0 ?? 1 !! $exit-code;
            $log ~= "»»»»» Final exit code: $final-exit-code\n";
            return $log, $final-exit-code;
        }
    }

    # compare the output
    $log ~= "»»»»» Bisecting by using the output\n";
    my $output-good = slurp $compare-to;
    $log ~= "»»»»» Comparing the output to:\n";
    $log ~= $output-good;
    if $output eq $output-good {
        $log ~= "\n»»»»» The output is identical\n";
        $log ~= "»»»»» Final exit code: 0\n";
        return $log, 0;
    } else {
        $log ~= "\n»»»»» The output is different\n";
        $log ~= "»»»»» Final exit code: 1\n";
        return $log, 1;
    }

    # looks a bit nicer this way
    LEAVE $log ~= "»»»»» -------------------------------------------------------------------------\n";
}

my regex spaceeq { \s* ‘=’ \s* | \s+ }
my regex bisect-cmd {
    ^ \s*
    [
        [ good <spaceeq> $<good>=\S+ \s* ]
        [ bad  <spaceeq> $<bad> =\S+ \s* ]?
        |
        [ bad  <spaceeq> $<bad> =\S+ \s* ]?
        [ good <spaceeq> $<good>=\S+ \s* ]?
    ]
    $<code>=.*
    $
}

multi method irc-to-me($message where { .text !~~ /:i ^ [help|source|url] ‘?’? $ | ^stdin /
                                        # ↑ stupid, I know. See RT #123577
                                        and .text ~~ &bisect-cmd}) {
    my $value = self.process($message, ~$<code>,
                             ~($<good> // ‘2015.12’), ~($<bad> // ‘HEAD’));
    return ResponseStr.new(:$value, :$message);
}

method process($message, $code is copy, $good, $bad) {
    my ($succeeded, $code-response) = self.process-code($code, $message);
    return $code-response unless $succeeded;
    $code = $code-response;

    # convert to real ids so we can look up the builds
    my $full-good = self.to-full-commit($good);
    return ‘Cannot find ‘good’ revision’ unless defined $full-good;
    my $short-good = self.get-short-commit($good eq $full-good | 'HEAD' ?? $full-good !! $good);
    return ‘No build for ‘good’ revision’ if not self.build-exists($full-good);

    my $full-bad = self.to-full-commit($bad);
    return ‘Cannot find ‘bad’ revision’ unless defined $full-bad;
    my $short-bad = self.get-short-commit($bad eq ‘HEAD’ ?? $full-bad !! $bad);
    return ‘No build for ‘bad’ revision’ if not self.build-exists($full-bad);

    my $filename = self.write-code($code);

    my $old-dir = $*CWD;
    chdir RAKUDO;
    my ($out-good, $exit-good, $signal-good, $time-good) = self.run-snippet($full-good, $filename);
    my ($out-bad,  $exit-bad,  $signal-bad,  $time-bad)  = self.run-snippet($full-bad,  $filename);
    chdir $old-dir;

    return “Problem with ‘good’ commit: $out-good” if $signal-good < 0;
    return “Problem with ‘bad’ commit: $out-bad”   if $signal-bad  < 0;

    $out-good //= ‘’;
    $out-bad  //= ‘’;

    if $exit-good == $exit-bad and $out-good eq $out-bad {
        $message.reply: “On both starting points (good=$short-good bad=$short-bad) the exit code is $exit-bad and the output is identical as well”;
        return “Output on both points: $out-good”; # will be gisted automatically if required
    }
    my $output-file = ‘’;
    if $exit-good == $exit-bad {
        $message.reply: “Exit code is $exit-bad on both starting points (good=$short-good bad=$short-bad), bisecting by using the output”;
        ($output-file, my $fh) = tempfile :!unlink;
        $fh.print: $out-good;
        $fh.close;
    }
    if $exit-good != $exit-bad and $exit-good != 0 {
        $message.reply: “For the given starting points (good=$short-good bad=$short-bad), exit code on a ‘good’ revision is $exit-good (which is bad), bisecting with inverted logic”;
    }

    my $dir = tempdir :!unlink;
    run(‘git’, ‘clone’, RAKUDO, $dir);
    chdir $dir;

    self.get-output(‘git’, ‘bisect’, ‘start’);
    self.get-output(‘git’, ‘bisect’, ‘good’, $full-good);
    my ($init-output, $init-status) = self.get-output(‘git’, ‘bisect’, ‘bad’, $full-bad);
    if $init-status != 0 {
        $message.reply: ‘bisect log: ’ ~ self.upload({ ‘query’       => $message.text,
                                                       ‘result’      => $init-output, },
                                                     description => $message.server.current-nick);
        return ‘bisect init failure’;
    }
    my ($bisect-output, $bisect-status);
    if $output-file {
        ($bisect-output, $bisect-status)     = self.run-bisect($filename, $output-file);
    } else {
        if $exit-good == 0 {
            ($bisect-output, $bisect-status) = self.run-bisect($filename);
        } else {
            ($bisect-output, $bisect-status) = self.run-bisect($filename, $exit-good);
        }
    }
    $message.reply: ‘bisect log: ’ ~ self.upload({ ‘query’       => $message.text,
                                                   ‘result’      => “$init-output\n$bisect-output”, },
                                                 description => $message.server.current-nick);

    if $bisect-status != 0 {
        return “‘bisect run’ failure”;
    } else {
        return self.get-output(‘git’, ‘show’, ‘--quiet’, ‘--date=short’, “--pretty=(%cd) {LINK}/%h”, ‘bisect/bad’).first;
    }

    LEAVE {
        chdir  $old-dir     if defined $old-dir;
        unlink $output-file if defined $output-file and $output-file.chars > 0;
        unlink $filename    if defined $filename    and $filename.chars    > 0;
        rmtree $dir         if defined $dir         and $dir.chars         > 0;
        sleep 0.02; # otherwise the output may be in the wrong order TODO is it a problem in IRC::Client?
    }
}

Bisectable.new.selfrun(‘bisectable6’, [‘bisect’, ‘bisect6’]);

# vim: expandtab shiftwidth=4 ft=perl6

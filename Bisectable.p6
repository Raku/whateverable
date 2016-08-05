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
use IRC::Client;

unit class Bisectable is Whateverable;

constant LINK          = ‘https://github.com/rakudo/rakudo/commit’;
constant COMMIT-TESTER = ‘./test-commit’.IO.absolute;
constant BUILD-LOCK    = ‘./lock’.IO.absolute;

method help($message) {
    ~ “Like this: {$message.server.current-nick}”
    ~ ‘: good=2015.12 bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT128181’
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

multi method irc-to-me($message where { .text !~~ /^ [help|source|url] ‘?’? $/
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

    if “{BUILDS}/$full-good/bin/perl6”.IO !~~ :e {
        if BUILD-LOCK.IO ~~ :e {
            # TODO make it possible to use bisectable while it is building something
            return ‘No build for ‘good’ revision. Right now the build process is in action, please try again later or specify some older ‘good’ commit (e.g., good=HEAD~10)’;
        }
        return ‘No build for ‘good’ revision’;
    }

    my $full-bad = self.to-full-commit($bad);
    my $short-bad = substr($bad eq ‘HEAD’ ?? $full-bad !! $bad, 0, 7);
    return ‘Cannot find ‘bad’ revision’ unless defined $full-bad;

    if “{BUILDS}/$full-bad/bin/perl6”.IO !~~ :e {
        if BUILD-LOCK.IO ~~ :e {
            # TODO make it possible to use bisectable while it is building something
            return ‘No build for ‘bad’ revision. Right now the build process is in action, please try again later or specify some older ‘bad’ commit (e.g., bad=HEAD~40)’;
        }
        return ‘No build for ‘bad’ revision’;
    }

    my $filename = self.write-code($code);

    my $old-dir = $*CWD;
    chdir RAKUDO;
    my ($out-good, $exit-good, $signal-good, $time-good) = self.get-output(“{BUILDS}/$full-good/bin/perl6”, $filename);
    my ($out-bad,  $exit-bad,  $signal-bad,  $time-bad)  = self.get-output(“{BUILDS}/$full-bad/bin/perl6”,  $filename);
    chdir $old-dir;
    $out-good //= ‘’;
    $out-bad //=  ‘’;

    if $exit-good == $exit-bad and $out-good eq $out-bad {
        $message.reply: “On both starting points (good=$good bad=$short-bad) the exit code is $exit-bad and the output is identical as well”;
        return “Output on both points: $out-good”; # will be gisted automatically if required
    }
    my $output-file = ‘’;
    if $exit-good == $exit-bad {
        $message.reply: “Exit code is $exit-bad on both starting points (good=$good bad=$short-bad), bisecting by using the output”;
        ($output-file, my $fh) = tempfile :unlink;
        $fh.print: $out-good;
        $fh.close;
    }
    if $exit-good != $exit-bad and $exit-good != 0 {
        $message.reply: “For the given starting points (good=$good bad=$short-bad), exit code on a ‘good’ revision is $exit-good (which is bad), bisecting with inverted logic”;
    }

    my $dir = tempdir :unlink;
    run(‘git’, ‘clone’, RAKUDO, $dir);
    chdir($dir);

    self.get-output(‘git’, ‘bisect’, ‘start’);
    self.get-output(‘git’, ‘bisect’, ‘good’, $full-good);
    my ($init-output, $init-status) = self.get-output(‘git’, ‘bisect’, ‘bad’, $full-bad);
    if $init-status != 0 {
        chdir($old-dir);
        $message.reply: ‘bisect log: ’ ~ self.upload({ ‘query’  => $message.text,
                                                       ‘result’ => $init-output });
        return ‘bisect init failure’;
    }
    my ($bisect-output, $bisect-status);
    if $output-file {
        ($bisect-output, $bisect-status)     = self.get-output(‘git’, ‘bisect’, ‘run’,
                                                               COMMIT-TESTER, BUILDS, $filename, $output-file);
    } else {
        if $exit-good == 0 {
            ($bisect-output, $bisect-status) = self.get-output(‘git’, ‘bisect’, ‘run’,
                                                               COMMIT-TESTER, BUILDS, $filename);
        } else {
            ($bisect-output, $bisect-status) = self.get-output(‘git’, ‘bisect’, ‘run’,
                                                               COMMIT-TESTER, BUILDS, $filename, $exit-good);
        }
    }
    $message.reply: ‘bisect log: ’ ~ self.upload({ ‘query’  => $message.text,
                                                   ‘result’ => “$init-output\n$bisect-output” });
    if $bisect-status != 0 {
        chdir($old-dir);
        return “‘bisect run’ failure”;
    }
    my ($result) = self.get-output(‘git’, ‘show’, ‘--quiet’, ‘--date=short’, “--pretty=(%cd) {LINK}/%h”, ‘bisect/bad’);
    chdir($old-dir);
    return $result;
}

my $plugin = Bisectable.new;
my $nick = ‘bisectable6’;

.run with IRC::Client.new(
    :$nick
    :userreal($nick.tc)
    :username($nick.tc)
    :host<irc.freenode.net>
    :channels(%*ENV<DEBUGGABLE> ?? <#whateverable> !! <#perl6 #perl6-dev>)
    :debug(?%*ENV<DEBUGGABLE>)
    :plugins($plugin)
    :filters( -> |c { $plugin.filter(|c) } )
);

# vim: expandtab shiftwidth=4 ft=perl6

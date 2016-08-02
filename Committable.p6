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

unit class Committable is Whateverable;

constant LIMIT = 1000;

method help($message) {
    “Like this: {$message.server.current-nick}: f583f22,HEAD say ‘hello’; say ‘world’”
};

multi method irc-to-me($message where .text ~~ /^ \s* $<config>=\S+ \s+ $<code>=.+ /) {
    my $answer = self.process($message, ~$<config>, ~$<code>);
    return ResponseStr.new(value => $answer, message => $message);
}

method process($message, $config, $code is copy) {
    my @commits;
    if $config ~~ / ‘,’ / {
        @commits = $config.split: ‘,’;
    } elsif $config ~~ /^ $<start>=\S+ ‘..’ $<end>=\S+ $/ {
        my $old_dir = $*CWD;
        chdir RAKUDO;
        return ‘Bad start’ if run(‘git’, ‘rev-parse’, ‘--verify’, $<start>).exitcode != 0;
        return ‘Bad end’   if run(‘git’, ‘rev-parse’, ‘--verify’, $<end>).exitcode   != 0;
        my ($result, $exit-status, $exit-signal, $time) = self.get-output(‘git’, ‘rev-list’, “$<start>^..$<end>”);
        chdir $old_dir;

        return ‘Couldn't find anything in the range’ if $exit-status != 0;

        @commits = $result.split: “\n”;
        my $num-commits = @commits.elems;
        return “Too many commits ($num-commits) in range, you're only allowed {LIMIT}” if $num-commits > LIMIT;
    } elsif $config ~~ /:i releases / {
        @commits = <2015.10 2015.11 2015.12 2016.02 2016.03 2016.04 2016.05 2016.06 2016.07 HEAD>;
    } else {
        @commits = $config;
    }

    my ($succeeded, $code-response) = self.process-code($code, $message);
    return $code-response unless $succeeded;
    $code = $code-response;

    my $filename = self.write-code($code);

    my @result;
    my %lookup;
    for @commits -> $commit {
        # convert to real ids so we can look up the builds
        my $full-commit = self.to-full-commit($commit);
        my $out = ‘’;
        if not defined $full-commit {
            $out = ‘Cannot find this revision’;
        } elsif “{BUILDS}/$full-commit/bin/perl6”.IO !~~ :e {
            say “{BUILDS}/$full-commit/bin/perl6”;
            $out = ‘No build for this commit’;
        } else { # actually run the code
            ($out, my $exit, my $signal, my $time) = self.get-output(“{BUILDS}/$full-commit/bin/perl6”, $filename);
            $out ~= “ «exit code = $exit»” if $exit != 0;
            $out ~= “ «exit signal = {Signal($signal)} ($signal)»” if $signal != 0;
        }
        my $short-commit = $commit.substr(0, 7);

        # Code below keeps results in order. Example state:
        # @result = [ { commits => [‘A’, ‘B’], output => ‘42‘ },
        #             { commits => [‘C’],      output => ‘69’ }, ];
        # %lookup = { ‘42’ => 0, ‘69’ => 1 }
        if not %lookup{$out}:exists {
            %lookup{$out} = +@result;
            @result.push: { commits => [$short-commit], output => $out };
        } else {
            say “Lookup(out): %lookup{$out}”;
            @result[%lookup{$out}]<commits>.push: $short-commit;
        }
    }

    my $msg-response = ‘¦’ ~ @result.map({ “«{.<commits>.join(‘,’)}»: {.<output>}” }).join(“\n¦”);
    return $msg-response;
}

my $plugin = Committable.new;
my $nick = ‘committable6’;

.run with IRC::Client.new(
    :nick($nick)
    :userreal($nick.tc)
    :username($nick.tc)
    :host<irc.freenode.net>
    :channels(%*ENV<DEBUGGABLE> ?? <#whateverable> !! <#perl6 #perl6-dev>)
    :debug(?%*ENV<DEBUGGABLE>)
    :plugins($plugin)
    :filters( -> |c { $plugin.filter(|c) } )
);

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
use Whateverable;

use IRC::Client;

unit class Committable does Whateverable;

constant TOTAL-TIME = 60 × 3;
constant shortcuts = %(
    mc  => ‘2015.12’,      ec  => ‘2015.12’,
    mch => ‘2015.12,HEAD’, ech => ‘2015.12,HEAD’,
    ma  => ‘all’, all => ‘all’,
    what => ‘6c’, ‘6c’ => ‘6c’, ‘v6c’ => ‘6c’, ‘v6.c’ => ‘6c’, ‘6.c’ => ‘6c’,
);

method help($msg) {
    “Like this: {$msg.server.current-nick}: f583f22,HEAD say ‘hello’; say ‘world’”
}

multi method irc-to-me($msg where .args[1] ~~ ?(my $prefix = m/^ $<shortcut>=<{shortcuts.keys}>
                                                                 $<delim>=[‘:’ | ‘,’]/)
                                  && .text ~~ /^ \s* $<code>=.+ /) is default {
    return if $prefix<delim> eq ‘,’;
    my $value = self.process: $msg, shortcuts{$prefix<shortcut>}, ~$<code>;
    return without $value;
    return $value but Reply($msg)
}

multi method irc-to-me($msg where { .text ~~ /^ \s* $<config>=\S+ \s+ $<code>=.+ / }) {
    my $value = self.process: $msg, ~$<config>, ~$<code>;
    return without $value;
    return $value but Reply($msg)
}

method process($msg, $config is copy, $code is copy) {
    my $old-dir = $*CWD;
    my $start-time = now;

    if $config ~~ /^ [say|sub] $/ {
        $msg.reply: “Seems like you forgot to specify a revision (will use “v6.c” instead of “$config”)”;
        $code = “$config $code”;
        $config = ‘v6.c’
    }

    my ($commits-status, @commits) = self.get-commits: $config;
    return $commits-status unless @commits;

    my ($succeeded, $code-response) = self.process-code: $code, $msg;
    return $code-response unless $succeeded;
    $code = $code-response;

    my $filename = self.write-code: $code;

    my @result;
    my %lookup;
    for @commits -> $commit {
        # convert to real ids so we can look up the builds
        my $full-commit = self.to-full-commit: $commit;
        my $output = ‘’;
        if not defined $full-commit {
            $output = ‘Cannot find this revision’;
            my @options = <HEAD v6.c releases all>;
            $output ~= “ (did you mean “{self.get-short-commit: self.get-similar: $commit, @options}”?)”
        } elsif not self.build-exists: $full-commit {
            $output = ‘No build for this commit’
        } else { # actually run the code
            my $result = self.run-snippet: $full-commit, $filename;
            $output = $result<output>;
            if $result<signal> < 0 { # numbers less than zero indicate other weird failures
                $output = “Cannot test this commit ($output)”
            } else {
                $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
                $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0
            }
        }
        my $short-commit = self.get-short-commit: $commit;
        $short-commit ~= “({self.get-short-commit: $full-commit})” if $commit eq ‘HEAD’;

        # Code below keeps results in order. Example state:
        # @result = [ { commits => [‘A’, ‘B’], output => ‘42‘ },
        #             { commits => [‘C’],      output => ‘69’ }, ];
        # %lookup = { ‘42’ => 0, ‘69’ => 1 }
        if not %lookup{$output}:exists {
            %lookup{$output} = +@result;
            @result.push: %( commits => [$short-commit], :$output )
        } else {
            @result[%lookup{$output}]<commits>.push: $short-commit
        }

        if now - $start-time > TOTAL-TIME {
            return “«hit the total time limit of {TOTAL-TIME} seconds»”
        }
    }

    my $short-str = @result == 1 && @result[0]<commits> > 3 && $config.chars < 20
    ?? “¦{$config} ({+@result[0]<commits>} commits): «{@result[0]<output>}»”
    !! ‘¦’ ~ @result.map({ “{.<commits>.join(‘,’)}: «{.<output>}»” }).join: ‘ ¦’;

    my $long-str  = ‘¦’ ~ @result.map({ “«{.<commits>.join(‘,’)}»: {.<output>}” }).join: “\n¦”;
    return $short-str but ProperStr($long-str);

    LEAVE {
        chdir $old-dir;
        unlink $filename if defined $filename and $filename.chars > 0
    }
}

Committable.new.selfrun: ‘committable6’, [ /commit6?/, fuzzy-nick(‘committable6’, 3),
                                           ‘c’, |shortcuts.keys ]

# vim: expandtab shiftwidth=4 ft=perl6

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

unit class Quotable does Whateverable;

constant $CACHE-FILE = ‘data/irc/cache’;
constant $LIMIT = 5_000;

method help($msg) {
    “Like this: {$msg.server.current-nick}: /^ ‘bisect: ’ /”
}

multi method irc-to-me($msg where /^ \s* [ ‘/’ $<regex>=[.*] ‘/’ || $<regex>=[.*?] ] \s* $/) {
    self.process: $msg, ~$<regex>
}

method process($msg, $query is copy) {
    $query = “/ $query /”;

    my $full-commit = self.to-full-commit: ‘2016.10’; # ‘HEAD’; # Ha, 2016.10 works a bit better for this purpose…
    die ‘No build for the last commit. Oops!’ unless self.build-exists: $full-commit;

    my $magic = “\{ last if \$++ >= $LIMIT; print \$_, “\\0” \} for slurp(‘$CACHE-FILE’).split(“\\0”).grep:\n”;
    my $filename = self.write-code: $magic ~ $query;
    my $result = self.run-snippet: $full-commit, $filename, :180timeout;
    my $output = $result<output>;
    # numbers less than zero indicate other weird failures ↓
    grumble “Something went wrong ($output)” if $result<signal> < 0;

    $output ~= “ «exit code = $result<exit-code>»” if $result<exit-code> ≠ 0;
    $output ~= “ «exit signal = {Signal($result<signal>)} ($result<signal>)»” if $result<signal> ≠ 0;
    return $output if $result<exit-code> ≠ 0 or $result<signal> ≠ 0;

    my $count = 0;
    $output = $output.split(“\0”).grep({$count++; True}).join: “\n”;

    return “Cowardly refusing to gist more than $LIMIT lines” if $count ≥ $LIMIT; # TODO off by one somewhere
    return ‘Found nothing!’ unless $output;
    ‘’ but ProperStr($output)
}


Quotable.new.selfrun: ‘quotable6’, [ / quote6? <before ‘:’> /,
                                     fuzzy-nick(‘quotable6’, 2) ]

# vim: expandtab shiftwidth=4 ft=perl6

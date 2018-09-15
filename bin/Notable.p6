#!/usr/bin/env perl6
# Copyright © 2018
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
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

use IRC::Client;
use JSON::Fast;

unit class Notable does Whateverable;

my $db = %*ENV<TESTABLE> ?? $*TMPDIR.add(“notable{time}”) !! ‘data/notes’.IO;
END { $db.unlink if %*ENV<TESTABLE> }
my @shortcuts = ‘weekly’;
write %() unless $db.e;

method help($msg) {
    “Like this: {$msg.server.current-nick}: weekly rakudo is now 10x faster”
}

sub read()       { from-json slurp $db }
sub write(%data) {           spurt $db, to-json %data }

my regex topic is export { <[\w:_-]>+ }

sub timestampish { DateTime.now(:0timezone).truncated-to: ‘seconds’ }

multi method irc-to-me($msg where ‘list’) {
    my @topics = read.keys.sort;
    return “No notes yet” unless @topics;
    @topics.join(‘ ’) but ProperStr(@topics.join: “\n”)
}

multi method irc-to-me($msg where
                       { m:r/^ \s* [ || <?{.args[1].starts-with: @shortcuts.any ~ ‘:’}>
                                     || <topic> ] \s* $/ }) {
    my $topic = ~($<topic> // $msg.args[1].split(‘:’)[0]);
    my $data = read;
    return “No notes for “$topic”” if $data{$topic}:!exists;
    my @notes = $data{$topic}.map: {
        “$_<timestamp> <$_<nick>>: $_<text>”
    }
    ((“{s +@notes, ‘note’}: ” ~ @notes.join: ‘  ;  ’)
     but ProperStr(@notes.join: “\n”))
     but PrettyLink({“{s +@notes, ‘note’}: $_”})
}

my &clearish = {
    my @clear-commands = <clear reset delete default>;
    do if .args[1].starts-with: @shortcuts.any ~ ‘:’ {
        m/^ \s* @clear-commands \s* $/
    } else {
        m/^ \s* @clear-commands \s+ <topic> \s* $/
        ||
        m/^ \s* <topic> \s+ @clear-commands \s* $/
    }
}
multi method irc-to-me($msg where &clearish) {
    $/ = $msg ~~ &clearish;
    my $topic = ~($<topic> // $msg.args[1].split(‘:’)[0]);
    my $data = read;
    return “No notes for “$topic”” if $data{$topic}:!exists;
    my $suffix = ~timestampish;
    my $new-topic = $topic ~ ‘_’ ~ $suffix;
    $data{$new-topic} = $data{$topic};
    $data{$topic}:delete;
    write $data;
    “Moved existing notes to “$new-topic””
}

multi method irc-to-me($msg where
                       { m:r/^ \s* [|| <?{.args[1].starts-with: @shortcuts.any ~ ‘:’}>
                                    || <topic> \s+] $<stuff>=[.*] $/ }) {
    my $topic = ~($<topic> // $msg.args[1].split(‘:’)[0]);
    my $stuff = ~$<stuff>;
    my $data = read;
    $data{$topic}.push: %(
        text      => ~$stuff,
        timestamp => timestampish,
        nick      => $msg.nick,
    );
    write $data;
    ‘Noted!’
}


my %*BOT-ENV;

Notable.new.selfrun: ‘notable6’, [ / [note|@shortcuts]6? <before ‘:’> /,
                                   fuzzy-nick(‘notable6’, 1) ]

# vim: expandtab shiftwidth=4 ft=perl6

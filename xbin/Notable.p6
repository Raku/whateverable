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
use Whateverable::FootgunDB;

use IRC::Client;
use JSON::Fast;

unit class Notable does Whateverable;

# TODO use FootgunDB here
my $db = FootgunDB.new: name => ‘notable/notes’;
END { $db.clean }
my @shortcuts = ‘weekly’; # first shortcut here is the default topic

method help($msg) {
    “Like this: {$msg.server.current-nick}: weekly rakudo is now 10x as fast”
}
method private-messages-allowed() { True }

# XXX The logic here is a bit convoluted. It is meant to be a
#     zero-width match (only then things work), but I don't think this
#     was what I meant when I originaly wrote it.
my regex shortcut($msg) { <?{ my $shortcut = $msg.args[1].split(‘:’)[0];
                            make $shortcut if $msg.?channel and $shortcut eq @shortcuts.any }> }
my regex topic { <[\w:_-]>+ }

#| List topics
multi method irc-to-me($msg where ‘list’) {
    my @topics = $db.read.keys.sort;
    return ‘No notes yet’ unless @topics;
    @topics.join(‘ ’) but ProperStr(@topics.join: “\n”)
}

#| Get notes
multi method irc-to-me($msg where
                       { .Str ~~ m:r/^ \s* [ <shortcut($msg)> || <topic> ] \s* $/ }) {
    my $topic = ~($<topic> // $<shortcut>.made);
    my $data = $db.read;
    return “No notes for “$topic”” if $data{$topic}:!exists;
    my @notes = $data{$topic}.map: {
        “$_<timestamp> <$_<nick>>: $_<text>”
    }
    ((“{s +@notes, ‘note’}: ” ~ @notes.join: ‘  ;  ’)
     but ProperStr(@notes.join: “\n”))
     but PrettyLink({“{s +@notes, ‘note’}: $_”})
}

#| Clear notes
multi method irc-to-me($msg where
                       { .Str ~~ m:r/^
                         :my @commands = <clear reset delete default>;
                         [
                             ||     <shortcut($msg)> \s* @commands \s*
                             || \s* @commands        \s+ <topic>   \s*
                             || \s* <topic>          \s+ @commands \s*
                         ]
                         $/ }) {
    my $topic = ~($<topic> // $<shortcut>.made);
    my $data = $db.read;
    return “No notes for “$topic”” if $data{$topic}:!exists;
    my $suffix = ~timestampish;
    my $new-topic = $topic ~ ‘_’ ~ $suffix;
    $data{$new-topic} = $data{$topic};
    $data{$topic}:delete;
    $db.write: $data;
    “Moved existing notes to “$new-topic””
}

#| Add new topic
multi method irc-to-me($msg where
                       { .Str ~~ m:r/^ \s* [ ‘new-topic’ | ‘new-category’ ] \s+ <topic> \s* $/ }) {
    my $topic = ~$<topic>;
    my $data = $db.read;
    return “Topic “$topic” already exists” if $data{$topic}:exists;
    $data{$topic} = [];
    $db.write: $data;
    “New topic added (“$topic”)”
}

#| Add a note
multi method irc-to-me($msg where
                       { .Str ~~ m:r/^ \s* [<shortcut($msg)> || <topic> \s+] $<stuff>=[.*] $/ }) {
    my $topic = $<topic>;
    my $stuff = ~$<stuff>;
    my $data = $db.read;
    if $topic.defined and $data{~$topic}:!exists {
        # someone forgot to specify a topic, just default to the first shortcut
        $topic = @shortcuts.head;
        $stuff = $msg;
    }
    $topic //= $<shortcut>.made;
    $data{~$topic}.push: %(
        text      => ~$stuff,
        timestamp => timestampish,
        nick      => $msg.nick,
    );
    $db.write: $data;
    “Noted! ($topic)”
}


Notable.new.selfrun: ‘notable6’, [ / [@shortcuts]6? <before ‘:’> /,
                                   fuzzy-nick(‘notable6’, 1) ]

# vim: expandtab shiftwidth=4 ft=perl6

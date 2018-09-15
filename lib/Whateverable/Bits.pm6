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


# This file is a collection of tiny general purpose
# functions and other things.

role Helpful { method help($msg) { … } }

role Reply      { has $.msg              }
role ProperStr  { has $.long-str         }
role PrettyLink { has &.link-msg         }
role FileStore  { has %.additional-files }

sub shorten($str, $max, $cutoff=$max ÷ 2) is export {
    $max ≥ $str.chars ?? $str !! $str.substr(0, $cutoff - 1) ~ ‘…’
}

sub fuzzy-nick($nick, $distance) is export {
    use Text::Diff::Sift4;
    / \w+ <?{ sift4(~$/, $nick, 5) ~~ 1..$distance }> /
}

sub signal-to-text($signal) is export {
    “$signal ({$signal ?? Signal($signal) !! ‘None’})”
}

sub s($count, $word) is export {
    +$count ~ ‘ ’ ~ $word ~ ($count == 1 ?? ‘’ !! ‘s’)
}

sub markdown-escape($text) is export {
    # TODO is it correct? No, that's an ugly hack…
    $text.trans: (｢<｣,   ｢>｣,  ｢&｣,  ｢\｣,  ｢`｣,  ｢*｣,  ｢_｣,  ｢~｣,  ｢|｣) =>
                 (｢\<｣, ｢\>｣, ｢\&｣, ｢\\｣, ｢\`｣, ｢\*｣, ｢\_｣, ｢\~｣, ｢\|｣); # ｣);
}

sub html-escape($text) is export {
    $text.trans: (‘&’, ‘<’, ‘>’) => (‘&amp;’, ‘&lt;’, ‘&gt;’)
}

my token commit-list is export {
    [<-[\s] -[‘,’]>+]+ % [‘,’\s*]
}

sub time-left(Instant() $then, :$already-there?) is export {
    my $time-left = $then - now;
    return $already-there if $already-there and $time-left < 0;
    my ($seconds, $minutes, $hours, $days) = $time-left.polymod: 60, 60, 24;
    if not $days and not $hours {
        return ‘is just a few moments away’ unless $minutes;
        return “is in $minutes minute{‘s’ unless $minutes == 1}”;
    }
    my $answer = ‘in ’;
    $answer ~= “$days day{$days ≠ 1 ?? ‘s’ !! ‘’} and ” if $days;
    $answer ~= “≈$hours hour{$hours ≠ 1 ?? ‘s’ !! ‘’}”;
    $answer
}

#↓ Spurt into a tempfile.
sub write-code($code --> IO) is export {
    use File::Temp;
    my ($filename, $filehandle) = tempfile :!unlink;
    $filehandle.print: $code;
    $filehandle.close;
    $filename.IO
}

class Whateverable::X::HandleableAdHoc is X::AdHoc is export {}

sub grumble(|c) is export {
     Whateverable::X::HandleableAdHoc.new(payload => c).throw
}

# vim: expandtab shiftwidth=4 ft=perl6

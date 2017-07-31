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

use Text::Diff::Sift4;

role Helpful { method help($msg) { … } }

role Reply      { has $.msg              }
role ProperStr  { has $.long-str         }
role PrettyLink { has &.link-msg         }
role FileStore  { has %.additional-files }

sub shorten($str, $max, $cutoff=$max ÷ 2) is export {
    $max ≥ $str.chars ?? $str !! $str.substr(0, $cutoff - 1) ~ ‘…’
}

sub fuzzy-nick($nick, $distance) is export {
    / \w+ <?{ sift4(~$/, $nick, 5) ~~ 1..$distance }> /
}

sub signal-to-text($signal) is export {
    “$signal ({Signal($signal) // ‘None’})”
}

sub markdown-escape($text) is export {
    # TODO is it correct? No, that's an ugly hack…
    $text.trans: (｢<｣,   ｢>｣,  ｢&｣,  ｢\｣,  ｢`｣,  ｢*｣,  ｢_｣,  ｢~｣) =>
                 (｢\<｣, ｢\>｣, ｢\&｣, ｢\\｣, ｢\`｣, ｢\*｣, ｢\_｣, ｢\~｣); # ｣);
}

my token commit-list is export {
    [<-[\s] -[‘,’]>+]+ % [‘,’\s*]
}

class Whateverable::X::HandleableAdHoc is X::AdHoc is export {}

sub grumble(|c) is export {
     Whateverable::X::HandleableAdHoc.new(payload => c).throw
}

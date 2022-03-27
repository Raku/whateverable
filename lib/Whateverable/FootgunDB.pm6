# Copyright © 2018-2019
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

#| Simple dumb flat file database
unit class FootgunDB;

use JSON::Fast;

has Str  $.name;
has IO   $!db;
has Lock $!lock .= new;

method TWEAK {
    $!db = %*ENV<TESTABLE> ?? $*TMPDIR.add($!name ~ time) !! “data/$.name”.IO;
    self.write: %() unless $!db.e;
}
method clean {
    $!db.unlink if %*ENV<TESTABLE>
}

method read() {
    from-json slurp $!db
}
method write(%data) {
    spurt $!db, to-json :sorted-keys, %data
}
method read-write(&code) {
    $!lock.protect: {
        my %data := self.read;
        code %data;
        self.write: %data
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

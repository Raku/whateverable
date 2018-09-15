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

use JSON::Fast;

#↓ User-configurable variables for a bot
unit module Whateverable::Config;

our $CONFIG is export;

sub ensure-config($handle = $*IN) is export {
    $CONFIG //= from-json slurp $handle;

    # TODO use a special config file for tests
    $CONFIG<rakudo> //= (%*ENV<TESTABLE> // ‘’).contains(‘rakudo-mock’)
                            ?? ‘./t/data/rakudo’.IO.absolute
                            !! ‘./data/rakudo-moar’.IO.absolute;

    $CONFIG<stdin> = $CONFIG<default-stdin>;

    # TODO find a way to get rid of this code
    $CONFIG<repo-current-rakudo-moar> .= IO .= absolute;
    $CONFIG<repo-current-moarvm>      .= IO .= absolute;
    $CONFIG<archives-location>        .= IO .= absolute;
    $CONFIG<builds-location>          .= IO .= absolute;
    $CONFIG<moarvm>                   .= IO .= absolute;
    $CONFIG<bisectable><build-lock>   .= IO .= absolute;
}

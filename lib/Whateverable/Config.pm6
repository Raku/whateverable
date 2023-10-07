# Copyright © 2018-2023
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

sub ensure-required-config-values {
    $CONFIG<message-limit>        //= 390;
    $CONFIG<gist-limit>           //= 10_000;
    $CONFIG<commits-limit>        //= 500; # TODO this shouldn't be required
    $CONFIG<join-delay>           //= 0;
    $CONFIG<github>               //= {};
    $CONFIG<github><login>        //= ‘’;
    $CONFIG<github><access_token> //= ‘’;
    $CONFIG<irc>                  //= {};
    $CONFIG<irc><login>           //= ‘’;
    $CONFIG<irc><password>        //= ‘’;
    $CONFIG<channels>             //= <#raku #raku-dev #zofbot #moarvm>;
    $CONFIG<cave>                 //= Empty;
    $CONFIG<caregivers>           //= [];
    $CONFIG<source>               //= ‘There is no public repo yet!’;
    $CONFIG<wiki>                 //= ‘There is no documentation for me yet!’;
    $CONFIG<default-stdin>        //= ‘’;
    $CONFIG<sandbox-path>         //= ~$*TMPDIR.add(‘whateverable’).add(‘sandbox’);
}

sub ensure-config($handle = $*IN) is export {
    if $CONFIG {
        ensure-required-config-values;
        return;
    }
    $CONFIG //= from-json slurp $handle;
    ensure-required-config-values;

    # TODO use a special config file for tests
    $CONFIG<projects><rakudo-moar><repo-path> = $CONFIG<projects><rakudo-moar><repo-path>
                                                 // ((%*ENV<TESTABLE> // ‘’).contains(‘rakudo-mock’)
                                                     ?? ‘./t/data/rakudo’ !! ‘./data/rakudo-moar’);

    $CONFIG<stdin> = $CONFIG<default-stdin>;

    # TODO find a way to get rid of this code
    $CONFIG<projects><rakudo-moar><repo-path>     .= IO .= absolute;
    $CONFIG<projects><rakudo-moar><archives-path> .= IO .= absolute;
    $CONFIG<projects><moarvm><repo-path>          .= IO .= absolute;
    $CONFIG<projects><moarvm><archives-path>      .= IO .= absolute;

    $CONFIG<builds-location>          .= IO .= absolute;
    $CONFIG<bisectable><build-lock>   .= IO .= absolute;
}

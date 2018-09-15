# Copyright © 2016-2018
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

unit module Whateverable::Heartbeat;

#↓ Tells the watchdog that we're still rolling.
sub I'm-alive is export {
    return if %*ENV<TESTABLE> or %*ENV<DEBUGGABLE>;
    use NativeCall;
    sub sd_notify(int32, str --> int32) is native(‘systemd’) {*};
    sd_notify 0, ‘WATCHDOG=1’; # this may be called too often, see TODO below
}

#↓ Asks the test suite to delay the test failure (for 0.5s)
sub test-delay is export {
    use NativeCall;
    sub kill(int32, int32) is native {*};
    sub getppid(--> int32) is native {*};
    my $sig-compat = SIGUSR1;
    # ↓ Fragile platform-specific hack
    $sig-compat = 10 if $*PERL.compiler.version ≤ v2018.05;
    kill getppid, +$sig-compat; # SIGUSR1
}

# vim: expandtab shiftwidth=4 ft=perl6

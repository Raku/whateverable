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

use Whateverable::Bits;

#↓ User-configurable variables for a bot
unit role Whateverable::Configurable;

# Keep in mind that the variables are not saved anywhere and will
# be reset on bot restart.

# This role expects the class to have %.variables attribute.

has %!default-values; #← autopopulated based on the first encountered value

#↓ Resetting a variable
multi method irc-to-me($msg where /^ $<key>=@(%*BOT-ENV.keys)
                                     ‘=’
                                     [‘’|clear|reset|delete|default] $/) {
    my $key   = ~$<key>;
    if %!default-values{$key}:!exists {
        # nothing to do
    } else {
        %*BOT-ENV{$key} = %!default-values{$key};
    }
    “$key is now set to its default value “{%*BOT-ENV{$key}}””
}

#↓ Setting a variable
multi method irc-to-me($msg where /^ $<key>=@(%*BOT-ENV.keys)
                                     ‘=’
                                     $<value>=\S+ $/) {
    my $key   = ~$<key>;
    my $value = ~$<value>;
    if %!default-values{$key}:!exists {
        %!default-values{$key} = %*BOT-ENV{$key}
    }
    my $default-value = %!default-values{$key};
    %*BOT-ENV{$key} = $value;
    “$key is now set to “$value” (default value is “$default-value”)”
}

#↓ Listing all variables
multi method irc-to-me($msg where ‘variables’|‘vars’) {
    my @vars  = %*BOT-ENV.sort(*.key);
    my $gist  = @vars.map({.key ~ ‘=’ ~ .value}).join(‘; ’);
    my $table = “| Name | Value |\n|---|---|\n”
              ~ join “\n”, @vars.map: {  “| {markdown-escape .key  } |”
                                        ~ “ {markdown-escape .value} |” };

    $gist but FileStore(%(‘variables.md’ => $table))
}

# vim: expandtab shiftwidth=4 ft=perl6

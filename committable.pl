#!/usr/bin/env perl
# Copyright © 2016
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
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

use v5.10;
use strict;
use warnings;
use utf8;

package Committable;
use parent 'Perl6IRCBotable';

my $name = 'committable';

sub process_message {
  my ($self, $message, $body) = @_;

  my $response = '';

  if ($body =~ /^ \s* (\S+) \s+ (.+) /xu) {
    my @commits = split(',', $1);
    my $code = $2;

    my $filename = $self->write_code($code);

    for my $commit (@commits) {
      # convert to real ids so we can look up the builds
      my $full_commit = $self->to_full_commit($commit);
      unless (defined $full_commit) {
        $response .= "Cannot find revision:$commit ";
        next;
      }

      my ($out, $err, $exit) = $self->get_output($self->BUILDS . "/$full_commit/bin/perl6 $filename");
      $out =~ s/\n/␤/g if (defined $out);
      $err =~ s/\n/␤/g if (defined $err);

      $response .= "$commit: stdout = '" . ($out // '') . "' ";
      $response .= "exit code = $exit, stderr = '" . ($err // '') . "' " if ($exit != 0);
    }
  } else {
    $response = help();
  }

  return $response;
}

sub help {
  "Like this: $name: f583f22,HEAD say 'hello'; say 'world'";
}

Committable->new(
  server      => '127.0.0.1',
  port        => '6667',
  channels    => ['#perl6-dev'],
  nick        => $name,
  alt_nicks   => [$name . '2', $name . '3'],
  username    => ucfirst $name,
  name        => 'Run code with a specific revision of Rakudo',
  ignore_list => [],
    )->run();

# vim: expandtab shiftwidth=2 ft=perl

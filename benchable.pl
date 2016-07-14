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

package Benchable;
use parent 'Perl6IRCBotable';

use Cwd qw(cwd abs_path);
use List::Util qw(min);

my $name = 'benchable';

sub process_message {
  my ($self, $message, $body) = @_;

  my $msg_response = '';

  if ($body =~ /^ \s* (\S+) \s+ (.+) /xu) {
    my @commits = split(',', $1);
    my $code = $2;

    my ($succeeded, $code_response) = $self->process_code($code, $message);
    if ($succeeded) {
      $code = $code_response;
    } else {
      return $code_response;
    }

    my $filename = $self->write_code($code);

    my %times;
    for my $commit (@commits) {
      # convert to real ids so we can look up the builds
      my $full_commit = $self->to_full_commit($commit);
      unless (defined $full_commit) {
        $msg_response .= "Cannot find revision:$commit ";
        next;
      }

      my $old_dir = cwd();
      chdir $self->RAKUDO;

      for (1..5) {
        my ($out, $exit, $time) = $self->get_output($self->BUILDS . "/$full_commit/bin/perl6", $filename);
        push @{$times{$commit}}, $time if ($exit == 0);
      }
      $times{$commit} = min(@{$times{$commit}});

      chdir $old_dir;
    }

    $msg_response .= join(' ', map { "$_=$times{$_}" } @commits);
  } else {
    return help();
  }

  return $msg_response;
}

sub help {
  'Like this: ' . $name . ': f583f22,110704d my $a = "a" x 2**16;for ^100000 {my $b = $a.chop($_)}'
}

Benchable->new(
  server      => 'irc.freenode.net',
  port        => '6667',
  channels    => ['#perl6', '#perl6-dev'],
  nick        => $name,
  alt_nicks   => [$name . '2', $name . '3', 'bench'],
  username    => ucfirst $name,
  name        => 'Time code with specific revisions of Rakudo',
  ignore_list => [],
    )->run();

# vim: expandtab shiftwidth=2 ft=perl

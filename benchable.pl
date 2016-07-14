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
    my ($config, $code) = ($1, $2);

    my @commits;
    if ($config =~ /,/) {
      @commits = split(',', $config);
    } elsif ($config =~ /^ (\S+) \.\. (\S+) $/x) {
      my ($start, $end) = ($1, $2);

      my $old_dir = cwd();
      chdir $self->RAKUDO;
      return "Bad start" if system('git', 'rev-parse', '--verify', $start) != 0;
      return "Bad end"   if system('git', 'rev-parse', '--verify', $end)   != 0;

      my ($result, $exit_status, $time) = $self->get_output('git', 'rev-list', "$start^..$end");
      chdir $old_dir;

      return "Couldn't find anything in the range" if $exit_status != 0;

      @commits = split("\n", $result);
      my $num_commits = scalar @commits;
      return "Too many commits ($num_commits) in range, you're only allowed 5" if ($num_commits > 5);
    } else {
      @commits = $config;
    }

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
  'Like this: ' . $name . ': f583f22,110704d my $a = "a" x 2**16;for ^1000 {my $b = $a.chop($_)}'
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

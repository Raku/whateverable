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

use Cwd qw(cwd abs_path);
use Encode qw(decode_utf8);

use constant LIMIT => 300;

my $name = 'committable';

sub timeout {
  return 50;
}

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

      my ($result, $exit_status, $exit_signal, $time) = $self->get_output('git', 'rev-list', "$start^..$end");
      chdir $old_dir;

      return "Couldn't find anything in the range" if $exit_status != 0;

      @commits = split("\n", $result);
      my $num_commits = scalar @commits;
      return "Too many commits ($num_commits) in range, you're only allowed " . LIMIT if ($num_commits > LIMIT);
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

    my @result;
    my %lookup;
    for my $commit (@commits) {
      # convert to real ids so we can look up the builds
      my $full_commit = $self->to_full_commit($commit);
      my $out = '';
      if (not defined $full_commit) {
        $out = "Cannot find this revision";
      } elsif (not -e $self->BUILDS . "/$full_commit/bin/perl6") {
        $out = 'No build for this commit';
      } else { # actually run the code
        ($out, my $exit, my $signal, my $time) = $self->get_output($self->BUILDS . "/$full_commit/bin/perl6", $filename);
        $out = decode_utf8($out);
        $out .= " «exit code = $exit»" if ($exit != 0);
        $out .= " «exit signal = $signal»" if ($signal != 0);
      }
      my $short_commit = substr($commit, 0, 7);

      # Code below keeps results in order. Example state:
      # @result = [ { commits => ['A', 'B'], output => '42' },
      #             { commits => ['C'],      output => '69' }, ];
      # %lookup = { '42' => 0, '69' => 1 }
      if (not exists $lookup{$out}) {
        $lookup{$out} = $#result;
        push @result, { commits => [$short_commit], output => $out };
      } else {
        push @{@result[$lookup{$out}]->{commits}}, $short_commit;
      }
    }

    $msg_response .= '¦' . join("\n|", map { '«' . join(',', @{$_->{commits}}) . '»: ' . $_->{output} } @result);
  } else {
    $msg_response = help();
  }

  return $msg_response;
}

sub help {
  "Like this: $name: f583f22,HEAD say 'hello'; say 'world'";
}

Committable->new(
  server      => 'irc.freenode.net',
  port        => '6667',
  channels    => ['#perl6', '#perl6-dev'],
  nick        => $name,
  alt_nicks   => ['commit'],
  username    => ucfirst $name,
  name        => 'Run code with a specific revision of Rakudo',
  ignore_list => [],
    )->run();

# vim: expandtab shiftwidth=2 ft=perl

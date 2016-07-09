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
use base 'Bot::BasicBot';

use File::Temp qw( tempfile tempdir );
use Cwd qw(cwd abs_path);
use IO::Handle;
use IPC::Open3;
use HTTP::Tiny;
use Encode qw/decode_utf8/;
use List::Util qw(min);

my $link          = 'https://github.com/rakudo/rakudo/commit';
my $rakudo        = './rakudo';
my $builds        = abs_path './builds';
my $commit_tester = abs_path './test-commit';
my $build_lock    = abs_path './lock';


sub get_output {
  # TODO flag if stderr is needed
  my $pid = open3(\*IN, \*RESULT, \*RESULT, '/bin/bash');
  print IN "@_;exit\n";
  waitpid($pid, 0);
  my $exit_status = $? >> 8;
  my $out = do { local $/; <RESULT> };
  chomp $out;
  return ($out, $exit_status)
}

sub to_commit {
  my ($str) = @_;
  return if system('git', 'rev-parse', '--verify', $str) != 0;
  my ($result, $exit_status) = get_output('git', 'rev-list', '-1', $str);
  return if $exit_status != 0;
  return $result;
}

sub said {
  my ($self, $message) = @_;

  if ($message->{body} eq 'source') {
    return 'https://github.com/perl6/bisectbot';
  }

  my $start = defined $message->{address} ? '' : 'benchable:';
  if ($message->{body} =~ /^ $start \s*
                           ((?:[a-f0-9]{7,40},?)+)
                           \s+
                           (.+)
                          /xu) {
    if (defined $message->{address} and $message->{address} eq 'msg') {
      return 'Sorry, it is too private here';
    }
    my $answer_start = defined $message->{who} ? "$message->{who}: " : '';

    my $commits = $1;
    my $code = $2;
    if ($code =~ m{ ^https?:// }x ) {
      my $response = HTTP::Tiny->new->get($code); # $code is actually an url
      if (not $response->{success}) {
        return "${answer_start}it looks like an URL but for some reason I cannot download it"
            . " (HTTP status-code is $response->{status})";
      }
      if ($response->{headers}->{'content-type'} ne 'text/plain; charset=utf-8') {
        return "${answer_start}it looks like an URL, but mime type is “$response->{headers}->{'content-type'}”"
            . ' while I was expecting “text/plain; charset=utf-8”. I can only understand raw links, sorry.';
      }
      $code = decode_utf8 $response->{content};
      $self->say(
        channel => $message->{channel},
        body => "${answer_start}successfully fetched the code from the provided URL",
          );
    } else {
      $code =~ s/␤/\n/g;
    }

    my ($fh, $filename) = tempfile(UNLINK => 1);
    binmode $fh, ':encoding(UTF-8)';
    print $fh $code;
    close $fh;

    # TODO use --no-checkout ?
    my $oldDir = cwd;

    # convert to real ids so we can look up the builds
    my @full_commits;
    chdir($rakudo);
    for my $commit (split(',', $commits)) {
      my $full_commit = to_commit($commit);
      push @full_commits, $full_commit if defined $full_commit;
    }

	my %times;
    for my $full_commit (@full_commits) {
      for (1..5) {
        my ($out,  $exit)  = get_output("TIMEFORMAT=%R && time $builds/$full_commit/bin/perl6 $filename");
        push @{$times{$full_commit}}, $out if ($exit == 0);
      }
      $times{$full_commit} = min(@{$times{$full_commit}});
    }

    $self->say(
      channel => $message->{channel},
      body => ${answer_start} . join(' ', map { substr($_, 0, 7) . "=$times{$_}" } sort { $times{$a} <=> $times{$b} } keys %times),
        );
  }
}

sub help {
  'Like this: benchable: f583f22,110704d my $a = "a" x 2**16;for ^100000 {my $b = $a.chop($_)}'
}

Benchable->new(
  server    => 'irc.freenode.org',
  port      => '6667',
  channels  => ['#perl6-dev'],
  nick      => 'benchable',
  alt_nicks => ['benchable2', 'benchable3'],
  username  => 'Benchable',
  name      => 'Time code with specific revisions of Rakudo',
  ignore_list => [],
    )->run();

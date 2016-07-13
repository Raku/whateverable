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

package Perl6IRCBotable;
use base 'Bot::BasicBot';

use File::Temp qw(tempfile tempdir);
use Cwd qw(cwd abs_path);
use IO::Handle;
use IPC::Open3;
use HTTP::Tiny;
use Encode qw(decode_utf8);
use Time::HiRes qw(gettimeofday);

use constant RAKUDO => './rakudo';
use constant BUILDS => abs_path('./builds');
use constant SOURCE => 'https://github.com/perl6/bisectbot';

my $name = 'Perl6IRCBotable';

sub get_output {
  my $self = shift;

  my ($s_start, $usec_start) = gettimeofday();
  my $pid = open3(undef, \*RESULT, \*RESULT, @_);
  waitpid($pid, 0);
  my ($s_end, $usec_end) = gettimeofday();

  my $exit_status = $? >> 8;

  my $out = do { local $/; <RESULT> };
  chomp $out if defined $out;

  return ($out, $exit_status, $usec_end - $usec_start)
}

sub to_full_commit {
  my ($self, $commit) = @_;

  my $old_dir = cwd();
  chdir RAKUDO;
  my ($result, $exit_status, $time) = $self->get_output('git', 'rev-parse', '--verify', $commit);
  chdir $old_dir;

  return if $exit_status != 0;
  return $result;
}

sub write_code {
  my $self = shift;

  my ($fh, $filename) = tempfile(UNLINK => 1);
  binmode $fh, ':encoding(UTF-8)';
  print $fh @_;
  close $fh;
  return $filename;
}

sub process_message {
  my ($self, $message, $body) = @_;

  return;
}

sub process_url {
  my ($self, $url, $message) = @_;

  my $response = HTTP::Tiny->new->get($url); # $body is actually a url
  if (not $response->{success}) {
    return "$message->{who}:It looks like a URL, but for some reason I cannot download it"
         . " (HTTP status-code is $response->{status})",;
  }
  if ($response->{headers}->{'content-type'} ne 'text/plain; charset=utf-8') {
    return "$message->{who}:It looks like a URL, but mime type is '$response->{headers}->{'content-type'}'"
         . " while I was expecting 'text/plain; charset=utf-8'. I can only understand raw links, sorry.";
  }
  my $body = decode_utf8($response->{content});
  $self->say(
    channel => $message->{channel},
    body    => "Successfully fetched the code from the provided URL.",
    who     => $message->{who},
      );

  return $body;
}

sub upload_output {
  my ($self, $output) = @_;

  return;
}

sub said {
  my ($self, $message) = @_;

  return unless ($message->{address});

  if ($message->{body} eq 'source') {
    return SOURCE;
  }

  my $body = $message->{body};

  if ($message->{address} eq 'msg') {
    return 'Sorry, it is too private here';
  } else {
    if ($body =~ m{ ^https?:// }x ) {
      $body = $self->process_url($body, $message);
      return $body if ($body =~ / ^$message->{who}: /x);
    } else {
      $body =~ s/␤/\n/g;
    }

    my $response = $self->process_message($message, $body);
    $response = $self->upload_output($response) if (length $response > 200);

    $self->say(
      channel => $message->{channel},
      body    => $response,
      who     => $message->{who},
        );
  }
}

sub help {
  "Like this: $name: f583f22 say 'hello'; say 'world'";
}

1

# vim: expandtab shiftwidth=2 ft=perl

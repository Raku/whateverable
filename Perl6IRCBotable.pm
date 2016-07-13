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

use constant RAKUDO => './rakudo';
use constant BUILDS => abs_path('./builds');
use constant SOURCE => 'https://github.com/perl6/bisectbot';

my $name = 'Perl6IRCBotable';

sub get_output {
  my $self = shift;

  my $pid = open3(\*IN, \*OUT, \*ERR, '/bin/bash');
  say IN "@_;exit";
  waitpid($pid, 0);

  my $exit_status = $? >> 8;

  my $out = do { local $/; <OUT> };
  chomp $out if defined $out;

  my $err = do { local $/; <ERR> };
  chomp $err if defined $err;

  return ($out, $err, $exit_status)
}

sub to_full_commit {
  my ($self, $commit) = @_;

  my $old_dir = cwd();
  chdir RAKUDO;
  my ($result, $err, $exit_status) = $self->get_output("git rev-parse --verify $commit");
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
  my ($self, $body, $filename) = @_;

  if ($body =~ /^ \s* (\S+) \s+ (.+) /xu) {
    my $commit = $1;
    my $code = $2;

    # convert to real ids so we can look up the builds
    my $full_commit = $self->to_full_commit($commit);
    return "Cannot find such revision" unless defined $full_commit;

    my $filename = $self->write_code($code);

    my ($out, $err, $exit) = $self->get_output(BUILDS . "/$full_commit/bin/perl6", $filename);
    $out =~ s/\n/␤/g if defined $out;
    $err =~ s/\n/␤/g if defined $err;

    return $exit == 0 ? $out : "exit code = $exit: stdout = '" . $out // '' . "', stderr = '" . $err // '' . "'";
  } else {
    return help();
  }
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
      my $response = HTTP::Tiny->new->get($body); # $body is actually a url
      if (not $response->{success}) {
        return "$message->{who}: it looks like a URL, but for some reason I cannot download it"
             . " (HTTP status-code is $response->{status})",;
      }
      if ($response->{headers}->{'content-type'} ne 'text/plain; charset=utf-8') {
        return "$message->{who}: it looks like a URL, but mime type is '$response->{headers}->{'content-type'}'"
             . " while I was expecting 'text/plain; charset=utf-8'. I can only understand raw links, sorry.";
      }
      $body = decode_utf8($response->{content});
      $self->say(
        channel => $message->{channel},
        body    => "Successfully fetched the code from the provided URL.",
        who     => $message->{who},
          );
    } else {
      $body =~ s/␤/\n/g;
    }

    $self->say(
      channel => $message->{channel},
      body    => $self->process_message($message, $body),
      who     => $message->{who},
        );
  }
}

sub help {
  "Like this: $name: f583f22 say 'hello'; say 'world'";
}

1

# vim: expandtab shiftwidth=2 ft=perl

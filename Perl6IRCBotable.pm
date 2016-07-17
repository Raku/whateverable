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

use Cwd qw(cwd abs_path);
use Encode qw(encode_utf8 decode_utf8);
use File::Temp qw(tempfile tempdir);
use HTTP::Tiny;
use IO::Handle;
use IPC::Open3;
use JSON::XS;
use Net::GitHub;
use Time::HiRes qw(time);

use constant RAKUDO => abs_path('./rakudo');
use constant BUILDS => abs_path('./builds');
use constant CONFIG => abs_path('./config.json');
use constant SOURCE => 'https://github.com/perl6/bisectbot';

sub get_output {
  my $self = shift;

  my $s_start = time();
  my $pid = open3(undef, \*RESULT, \*RESULT, @_);
  waitpid($pid, 0);
  my $s_end = time();

  my $exit_status = $? >> 8;

  my $out = do { local $/; <RESULT> };
  chomp $out if defined $out;

  return ($out, $exit_status, $s_end - $s_start)
}

sub to_full_commit {
  my ($self, $commit) = @_;

  my $old_dir = cwd();
  chdir RAKUDO;
  return if system('git', 'rev-parse', '--verify', $commit) != 0; # make sure that $commit is valid
  my ($result, $exit_status, $time) = $self->get_output('git', 'rev-list', '-1', $commit); # use rev-list to handle tags
  chdir $old_dir;

  return if $exit_status != 0;
  return $result
}

sub write_code {
  my $self = shift;

  my ($fh, $filename) = tempfile(UNLINK => 1); # will unlink on program exit
  binmode $fh, ':encoding(UTF-8)';
  print $fh @_;
  close $fh;
  return $filename
}

sub process_message {
  my ($self, $message, $body) = @_;
  # Bot-specific code goes here
  return
}

sub process_url {
  my ($self, $url, $message) = @_;

  my $response = HTTP::Tiny->new->get($url); # $body is actually a url
  if (not $response->{success}) {
    return (0, "It looks like a URL, but for some reason I cannot download it"
             . " (HTTP status-code is $response->{status}).");
  }
  if ($response->{headers}->{'content-type'} ne 'text/plain; charset=utf-8') {
    return (0, "It looks like a URL, but mime type is '$response->{headers}->{'content-type'}'"
             . " while I was expecting 'text/plain; charset=utf-8'. I can only understand raw links, sorry.");
  }
  my $body = decode_utf8($response->{content});
  $self->say(
    channel => $message->{channel},
    body    => "Successfully fetched the code from the provided URL.",
    who     => $message->{who},
    address => 1,
      );

  return (1, $body)
}

sub process_code {
  my ($self, $code, $message) = @_;

  if ($code =~ m{ ^https?:// }x ) {
    my ($succeeded, $response) = $self->process_url($code, $message);
    return (0, $response) unless $succeeded;
    $code = $response;
  } else {
    $code =~ s/␤/\n/g;
  }

  return (1, $code)
}

sub get_config {
  my $config_contents = do {
    local $/;
    open my $fh, '<:encoding(UTF-8)', CONFIG or die "No config file found";
    <$fh>;
  };

  my $config = decode_json $config_contents; # TODO do it only once
  return $config
}

sub upload {
  my ($self, $files) = @_;

  my $config = get_config;
  my $github = Net::GitHub->new(
    login => $config->{'login'},
    access_token => $config->{'access_token'},
  );

  my $gist = $github->gist;

  my %files_param = map { $_ => { 'content' => encode_utf8($files->{$_}) } } keys %$files; # github format

  my $res = $gist->create(
    {
      'description' => $self->nick,
      'public'      => 'true',
      'files'       => \%files_param,
    });

  return $res->{html_url}
}

sub said {
  my ($self, $message) = @_;
  my $body = $message->{body};

  return unless $message->{address};
  return SOURCE if $body eq 'source';
  return 'Sorry, it is too private here' if $message->{address} eq 'msg';

  my ($response, $additional_files) = $self->process_message($message, $body);
  if (length $response > 250 or defined $additional_files) { # upload code somewhere if the output is way too long
    $response = $self->upload({ 'query'  => $body,
                                'result' => $response,
                                %{$additional_files // {}}, });
  } else {
    $response =~ s/\n/␤/g;
  }

  $self->tell($message, $response);
}

sub tell {
  my ($self, $message, $text) = @_;
  $self->say(
    channel => $message->{channel},
    body    => $text,
    who     => $message->{who},
    address => 1,
      );
}

1

# vim: expandtab shiftwidth=2 ft=perl

#!/usr/bin/env perl
# Copyright © 2016
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

use v5.10;
use strict;
use warnings;
use utf8;

package Bisectable;
use base 'Bot::BasicBot';

use File::Temp qw( tempfile tempdir );
use Cwd qw(cwd abs_path);
use IO::Handle;
use IPC::Open3;
use HTTP::Tiny;
use Encode qw/decode_utf8/;

my $link          = 'https://github.com/rakudo/rakudo/commit';
my $rakudo        = './rakudo';
my $builds        = abs_path './builds';
my $commit_tester = abs_path './test-commit';
my $build_lock    = abs_path './lock';


sub get_output {
  # TODO flag if stderr is needed
  my $pid = open3(undef, \*RESULT, \*RESULT, @_);
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

  my $start = defined $message->{address} ? '' : 'bisect:';
  if ($message->{body} =~ /^ $start \s*
                           (?:
                             (?: good (?: \s*=\s* | \s+) ([^\s]+) \s+ )
                             (?: bad  (?: \s*=\s* | \s+) ([^\s]+) \s+ )?
                           |
                             (?: bad  (?: \s*=\s* | \s+) ([^\s]+) \s+ )?
                             (?: good (?: \s*=\s* | \s+) ([^\s]+) \s+ )?
                           )
                           (*PRUNE)
                           (.+)
                          /xu) {
    if (defined $message->{address} and $message->{address} eq 'msg') {
      return 'Sorry, it is too private here';
    }
    my $answer_start = $message->{address} ? '' : "$message->{who}: ";

    my $good = $1 // $4 // '2015.12';
    my $bad  = $2 // $3 // 'HEAD';
    my $code = $5;
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
    chdir($rakudo);
    $good = to_commit($good);
    chdir($oldDir);
    return "${answer_start}cannot find such “good” revision" unless defined $good;
    return "${answer_start}no build for such “good” revision" if ! -e "$builds/$good/bin/perl6";
    chdir($rakudo);
    $bad = to_commit($bad);
    chdir($oldDir);
    return "${answer_start}cannot find such “bad” revision" unless defined $bad;
    if (! -e "$builds/$bad/bin/perl6" and -e $build_lock) {
      # TODO fix the problem when it is building new commits
      return "${answer_start}no build for such “bad” revision. Right now the build process is in action, please try again later or specify some older “bad” commit (e.g. bad=HEAD~40)";
    }
    return "${answer_start}no build for such “bad” revision" if ! -e "$builds/$bad/bin/perl6";

    my ($out_good, $exit_good) = get_output("$builds/$good/bin/perl6", $filename);
    my ($out_bad,  $exit_bad)  = get_output("$builds/$bad/bin/perl6",  $filename);
    if ($exit_good == $exit_bad and $out_good eq $out_bad) {
      return "${answer_start}on both starting points the exit code is $exit_bad and the output is identical as well";
    }
    my $output_file = '';
    if ($exit_good == $exit_bad) {
      $self->say(
        channel => $message->{channel},
        body => "${answer_start}exit code is $exit_bad on both starting points, bisecting by using the output",
          );
      (my $fh, $output_file) = tempfile(UNLINK => 1);
      print $fh $out_good;
      close $fh;
    }
    if ($exit_good != $exit_bad and $exit_good != 0) {
      $self->say(
        channel => $message->{channel},
        body => "${answer_start}exit code on a “good” revision is $exit_good (which is bad), bisecting with inverted logic",
          );
    }

    my $dir = tempdir(CLEANUP => 1);
    system('git', 'clone', $rakudo, $dir);
    chdir($dir);

    system('git', 'bisect', 'start');
    system('git', 'bisect', 'good', $good);
    system('git', 'bisect', 'bad',  $bad);
    my $bisect_status;
    if ($output_file) {
      $bisect_status = system('git', 'bisect', 'run', $commit_tester, $builds, $filename, $output_file);
    } else {
      if ($exit_good == 0) {
        $bisect_status = system('git', 'bisect', 'run', $commit_tester, $builds, $filename);
      } else {
        $bisect_status = system('git', 'bisect', 'run', $commit_tester, $builds, $filename, $exit_good);
      }
    }
    if ($bisect_status != 0) {
      chdir($oldDir);
      return "${answer_start}“bisect run” failure";
    }
    my ($result) = get_output('git', 'show', '--quiet', '--date=short', "--pretty=(%cd) $link/%h", 'bisect/bad');
    chdir($oldDir);
    return "${answer_start}$result";
  }
}

sub help {
  'Like this: bisect: good=2015.12 bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT 128181'
}

Bisectable->new(
  server    => 'irc.freenode.org',
  port      => '6667',
  channels  => ['#perl6', '#perl6-dev'],
  nick      => 'bisectable',
  alt_nicks => ['bisectable2', 'bisectable3'],
  username  => 'Bisectable',
  name      => 'Quick git bisect for Rakudo',
  ignore_list => [],
    )->run();

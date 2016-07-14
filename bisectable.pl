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

package Bisectable;
use parent 'Perl6IRCBotable';

use File::Temp qw(tempfile tempdir);
use Cwd qw(cwd abs_path);

my $name = 'bisectable';

my $link          = 'https://github.com/rakudo/rakudo/commit';
my $commit_tester = abs_path('./test-commit');
my $build_lock    = abs_path('./lock');

sub process_message {
  my ($self, $message, $body) = @_;

  if ($body =~ /^ \s*
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

    my $good = $1 // $4 // '2015.12';
    my $bad  = $2 // $3 // 'HEAD';
    my $code = $5;

    my ($succeeded, $code_response) = $self->process_code($code, $message);
    if ($succeeded) {
      $code = $code_response;
    } else {
      return $code_response;
    }

    # convert to real ids so we can look up the builds
    my $full_good = $self->to_full_commit($good);
    return "Cannot find 'good' revision" unless defined $full_good;

    if (! -e $self->BUILDS . "/$full_good/bin/perl6") {
      if (-e $build_lock) {
        # TODO fix the problem when it is building new commits
        return "No build for 'good' revision. Right now the build process is in action, please try again later or specify some older 'good' commit (e.g., good=HEAD~10)";
      } else {
        return "No build for 'good' revision";
      }
    }

    my $full_bad = $self->to_full_commit($bad);
    return "Cannot find 'bad' revision" unless defined $full_bad;

    if (! -e $self->BUILDS . "/$full_bad/bin/perl6") {
      if (-e $build_lock) {
        # TODO fix the problem when it is building new commits
        return "No build for 'bad' revision. Right now the build process is in action, please try again later or specify some older 'bad' commit (e.g., bad=HEAD~40)";
      } else {
        return "No build for 'bad' revision";
      }
    }

    my $filename = $self->write_code($code);

    my $old_dir = cwd();
    chdir $self->RAKUDO;
    my ($out_good, $exit_good, $time_good) = $self->get_output($self->BUILDS . "/$full_good/bin/perl6", $filename);
    my ($out_bad,  $exit_bad,  $time_bad)  = $self->get_output($self->BUILDS . "/$full_bad/bin/perl6",  $filename);
    chdir $old_dir;
    $out_good //= '';
    $out_bad  //= '';

    if ($exit_good == $exit_bad and $out_good eq $out_bad) {
      return "On both starting points the exit code is $exit_bad and the output is identical as well";
    }
    my $output_file = '';
    if ($exit_good == $exit_bad) {
      $self->say(
        channel => $message->{channel},
        body    => "Exit code is $exit_bad on both starting points, bisecting by using the output",
        who     => $message->{who},
          );
      (my $fh, $output_file) = tempfile(UNLINK => 1);
      print $fh $out_good;
      close $fh;
    }
    if ($exit_good != $exit_bad and $exit_good != 0) {
      $self->say(
        channel => $message->{channel},
        body    => "Exit code on a 'good' revision is $exit_good (which is bad), bisecting with inverted logic",
        who     => $message->{who},
          );
    }

    my $oldDir = cwd();
    my $dir = tempdir(CLEANUP => 1);
    system('git', 'clone', $self->RAKUDO, $dir);
    chdir($dir);

    system('git', 'bisect', 'start');
    system('git', 'bisect', 'good', $full_good);
    system('git', 'bisect', 'bad',  $full_bad);
    my $bisect_status;
    if ($output_file) {
      $bisect_status = system('git', 'bisect', 'run', $commit_tester, $self->BUILDS, $filename, $output_file);
    } else {
      if ($exit_good == 0) {
        $bisect_status = system('git', 'bisect', 'run', $commit_tester, $self->BUILDS, $filename);
      } else {
        $bisect_status = system('git', 'bisect', 'run', $commit_tester, $self->BUILDS, $filename, $exit_good);
      }
    }
    if ($bisect_status != 0) {
      chdir($oldDir);
      return "'bisect run' failure";
    }
    my ($result) = $self->get_output('git', 'show', '--quiet', '--date=short', "--pretty=(%cd) $link/%h", 'bisect/bad');
    chdir($oldDir);
    return $result;
  }
}

sub help {
  "Like this: $name: good=2015.12 bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT128181"
}

Bisectable->new(
  server   	  => 'irc.freenode.net',
  port     	  => '6667',
  channels    => ['#perl6', '#perl6-dev'],
  nick        => $name,
  alt_nicks   => [$name . '2', $name . '3', 'bisect'],
  username    => ucfirst $name,
  name        => 'Quick git bisect for Rakudo',
  ignore_list => [],
    )->run();

# vim: expandtab shiftwidth=2 ft=perl

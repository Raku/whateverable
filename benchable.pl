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
use Encode qw(encode_utf8);
use File::Temp qw(tempfile tempdir);
use List::Util qw(min max);
use Chart::Gnuplot;
use Statistics::Basic qw(mean stddev);
use Scalar::Util qw(looks_like_number);

use constant LIMIT => 300;
use constant ITERATIONS => 5;

my $name = 'benchable';

sub timeout {
  return 200;
}

sub benchmark_code {
  my ($self, $full_commit, $filename) = @_;

  my @times;
  my %stats;
  for (1..ITERATIONS) {
    my (undef, $exit, $signal, $time) = $self->get_output($self->BUILDS . "/$full_commit/bin/perl6", $filename);
    if ($exit == 0) {
      push @times, sprintf('%.4f', $time);
    } else {
      $stats{'err'} = "«run failed, exit code = $exit, exit signal = $signal»";
      return \%stats;
    }
  }

  $stats{'min'}    = min(@times);
  $stats{'max'}    = max(@times);
  $stats{'mean'}   = mean(@times);
  $stats{'stddev'} = stddev(@times);

  return \%stats;
}

sub process_message {
  my ($self, $message, $body) = @_;

  my $msg_response = '';
  my $graph = undef;

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
    } elsif (lc $config eq 'releases') {
      @commits = qw(2015.10 2015.11 2015.12 2016.02 2016.03 2016.04 2016.05 2016.06 2016.07 HEAD);
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
      my $short_commit = substr($commit, 0, 7);
      if (not defined $full_commit) {
        $times{$short_commit}{'err'} = 'Cannot find this revision';
      } elsif (not -e $self->BUILDS . "/$full_commit/bin/perl6") {
        $times{$short_commit}{'err'} = 'No build for this commit';
      } else { # actually run the code
        $times{$short_commit} = $self->benchmark_code($full_commit, $filename);
      }
    }

    # for these two config options, check if there are any large speed differences between two commits and if so, 
    # recursively find the commit in the middle until there are either no more large speed differences or no
    # more commits inbetween (i.e., the next commit is the exact one that caused the difference)
    if (lc $config eq 'releases' or $config =~ /,/) {
      my $old_dir = cwd();
      chdir $self->RAKUDO;

Z:    for (my $x = 0; $x < scalar @commits - 1; $x++) {
        next unless (exists $times{$commits[$x]} and exists $times{$commits[$x + 1]});          # the commits have to have been run at all
        next if (exists $times{$commits[$x]}{'err'} or exists $times{$commits[$x + 1]}{'err'}); # and without error
        if (abs($times{$commits[$x]}{'min'} - $times{$commits[$x + 1]}{'min'}) >= $times{$commits[$x]}{'min'}*0.1) {
          my ($new_commit, $exit_status, $exit_signal, $time) = $self->get_output('git', 'rev-list', '--bisect', $commits[$x] . '^..' . $commits[$x + 1]);
          if ($exit_status == 0 and defined $new_commit and $new_commit ne '') {
            my $short_commit = substr($new_commit, 0, 7);
            if (not -e $self->BUILDS . "/$new_commit/bin/perl6") {
              $times{$short_commit}{'err'} = 'No build for this commit';
            } elsif (!exists $times{$short_commit} and $short_commit ne $commits[$x] and $short_commit ne $commits[$x + 1]) { # actually run the code
              $times{$short_commit} = $self->benchmark_code($new_commit, $filename);
              splice(@commits, $x + 1, 0, $short_commit);
              redo Z;
            }
          }
        }
      }

      chdir $old_dir;
    }

    if (scalar @commits >= ITERATIONS) {
      my $gfilename = 'graph.svg';
      (my $title = $body) =~ s/"/\\"/g;
      my @ydata = map { $times{substr($_, 0, 7)}{'err'} // $times{substr($_, 0, 7)}{'min'} } @commits;
      my $chart = Chart::Gnuplot->new(
        output   => $gfilename,
        encoding => 'utf8',
        title	 => {
          text     => encode_utf8($title),
          enhanced => 'off',
        },
        size     => '2,1',
#        terminal => 'svg mousing',
        xlabel   => {
          text   => 'Commits\\nMean,Max,Stddev',
          offset => '0,-1',
        },
        xtics    => { labels => [map { my $commit = substr($commits[$_], 0, 7); "\"$commit\\n" . ($times{$commit}{'err'} // join(',', @{$times{$commit}}{qw(mean max stddev)})) . "\" $_" } 0..$#commits], },
        ylabel   => 'Seconds',
        yrange   => [0, max(grep { looks_like_number($_) } @ydata)*1.25],
          );
      my $dataSet = Chart::Gnuplot::DataSet->new(
        ydata => \@ydata,
        style => 'linespoints',
          );
      $chart->plot2d($dataSet);

      open my $gfh, '<', $gfilename or die $!;
      $graph->{$gfilename} = do {
        local $/;
        <$gfh>;
      };
    }

    $msg_response .= '¦' . join("\n¦", map { $_ = substr($_, 0, 7); "«$_»:" . ($times{$_}{'err'} // $times{$_}{'min'}) } @commits);
  } else {
    return help();
  }

  return ($msg_response, $graph);
}

sub help {
  'Like this: ' . $name . ': f583f22,110704d my $a = "a" x 2**16;for ^1000 {my $b = $a.chop($_)}'
}

Benchable->new(
  server      => 'irc.freenode.net',
  port        => '6667',
  channels    => ['#perl6', '#perl6-dev'],
  nick        => $name,
  alt_nicks   => ['bench'],
  username    => ucfirst $name,
  name        => 'Time code with specific revisions of Rakudo',
  ignore_list => [],
    )->run();

# vim: expandtab shiftwidth=2 ft=perl

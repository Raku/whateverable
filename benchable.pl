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

use constant LIMIT => 300;
use constant ITERATIONS => 5;

my $name = 'benchable';

sub timeout {
  return 200;
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
        $times{$short_commit} = 'Cannot find this revision';
      } elsif (not -e $self->BUILDS . "/$full_commit/bin/perl6") {
        $times{$short_commit} = 'No build for this commit';
      } else { # actually run the code
        for (1..ITERATIONS) {
          (undef, my $exit, my $signal, my $time) = $self->get_output($self->BUILDS . "/$full_commit/bin/perl6", $filename);
          push @{$times{$short_commit}}, $exit == 0 ? sprintf('%.4f', $time) : "«run failed, exit code = $exit, exit signal = $signal»";
        }
        my @times = @{$times{$short_commit}};
        $times{$short_commit} = {};
        $times{$short_commit}{'min'} = min(@times);
        $times{$short_commit}{'max'} = max(@times);
        $times{$short_commit}{'mean'} = mean(@times);
        $times{$short_commit}{'stddev'} = stddev(@times);
      }
    }

    if (scalar @commits >= ITERATIONS) {
      my ($gfh, $gfilename) = tempfile(SUFFIX => '.svg', UNLINK => 1);
      (my $title = $body) =~ s/"/\\"/g;
      my $chart = Chart::Gnuplot->new(
        output   => 'graph.svg',
        encoding => 'utf8',
        title	 => {
          text     => encode_utf8($title),
          enhanced => 'off',
        },
#        terminal => 'svg mousing',
        xlabel   => {
          text   => 'Commits\\nMean,Max,Stddev',
          offset => '0,-1',
        },
        ylabel   => 'Seconds',
        xtics    => { labels => [map { "\"$commits[$_]\\n" . join(',', @{$times{substr($commits[$_], 0, 7)}}{qw(mean max stddev)}) . "\" $_" } 0..$#commits], },
          );
      my $dataSet = Chart::Gnuplot::DataSet->new(
        ydata => [map { $times{substr($_, 0, 7)}{'min'} } @commits],
        style => 'linespoints',
          );
      $chart->plot2d($dataSet);

      $graph->{'graph.svg'} = do {
        local $/;
        <$gfh>;
      };
    }

    $msg_response .= '|' . join("\n|", map { $_ = substr($_, 0, 7); "«$_»:$times{$_}" } @commits);
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

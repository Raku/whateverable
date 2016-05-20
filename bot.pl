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

my $link          = 'https://github.com/rakudo/rakudo/commit';
my $rakudo        = './rakudo';
my $builds        = abs_path './builds';
my $commit_tester = abs_path './test-commit';

sub said {
  my ($self, $message) = @_;
  if ($message->{body} =~ /bisect:
                           (?:
                             (?: \s+ good (?: \s+ | \s*=\s*) ([\w\d.-]+) )
                             (?: \s+ bad  (?: \s+ | \s*=\s*) ([\w\d.-]+) )?
                           |
                             (?: \s+ bad  (?: \s+ | \s*=\s*) ([\w\d.-]+) )?
                             (?: \s+ good (?: \s+ | \s*=\s*) ([\w\d.-]+) )?
                           )
                           (*PRUNE)
                           \s+ (.+)
                          /xu) {
    if (defined $message->{address}) {
      return 'Sorry, it is too private here';
    }
    my $good = $1 // $4 // 'v6.c';
    my $bad  = $2 // $3 // 'HEAD';
    my $code = $5;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    binmode $fh, ':encoding(UTF-8)';
    print $fh $code;
    close $fh;

    my $dir = tempdir(CLEANUP => 1);
    # TODO use --no-checkout ?
    system('git', 'clone', $rakudo, $dir);
    my $oldDir = cwd;
    chdir($dir);
    system('git', 'bisect', 'start');
    system('git', 'bisect', 'good', $good);
    system('git', 'bisect', 'bad',  $bad);
    system('git', 'bisect', 'run',  $commit_tester, $builds, $filename);
    my $result = `git log -n 1 --date=short --pretty='(%cd) $link/%h'`;
    chdir($oldDir);

    return "$message->{who}: $result";
  }
}

sub help {
  'Like this: bisect: good=v6.c bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT 128181'
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

# Copyright © 2016-2018
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
# Copyright © 2016
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

use Whateverable::Bits;

unit module Whateverable::Output;

#↓ Fancy and overwhelming way of getting stdout+stderr of a command.
#↓ This is one of the most important subs in Whateverable.
sub get-output(*@run-args, :$timeout = %*BOT-ENV<timeout> // 10,
               :$stdin, :$ENV, :$cwd = $*CWD, :$chomp = True) is export {
    # Generally it's not a great idea to touch this sub. It works as is
    # and currently it is stable.
    my $proc = Proc::Async.new: |@run-args;

    my $fh-stdin;
    LEAVE .close with $fh-stdin;
    my $temp-file;
    LEAVE unlink $_ with $temp-file;
    with $stdin {
        if $stdin ~~ IO::Path {
            $fh-stdin = $stdin.open
        } elsif $stdin ~~ IO::Handle {
            $fh-stdin = $stdin
        } else {
            $temp-file = write-code $stdin;
            $fh-stdin = $temp-file.IO.open
        }
        $proc.bind-stdin: $fh-stdin
    }

    my $buf = Buf.new;
    my $result;
    my $s-start = now;
    my $s-end;
    react {
        whenever $proc.stdout :bin { $buf.push: $_ }; # RT #131763
        whenever $proc.stderr :bin { $buf.push: $_ };
        whenever Promise.in($timeout) {
            $proc.kill; # TODO sends HUP, but should kill the process tree instead
            $buf.push: “«timed out after $timeout seconds»”.encode
        }
        whenever $proc.start: :$ENV, :$cwd {
            $result = $_;
            $s-end = now;
            done
        }
    }

    my $output = $buf.decode: ‘utf8-c8’;
    %(
        output    => $chomp ?? $output.chomp !! $output,
        exit-code => $result.exitcode,
        signal    => $result.signal,
        time      => $s-end - $s-start,
    )
}

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

use JSON::Fast;
use HTTP::UserAgent;

use Whateverable::Bits;
use Whateverable::Builds;
use Whateverable::Running;

unit module Whateverable::Processing;

#↓ Runs $filename using some build on $full-commit and performs
#↓ some basic output formatting.
sub subprocess-commit($commit, $filename, $full-commit, :%ENV) is export {
    # TODO $commit unused
    return ‘No build for this commit’ unless build-exists $full-commit;

    $_ = run-snippet $full-commit, $filename, :%ENV; # actually run the code
    # numbers less than zero indicate other weird failures ↓
    return “Cannot test this commit ($_<output>)” if .<signal> < 0;
    my $output = .<output>;
    $output ~= “ «exit code = $_<exit-code>»” if .<exit-code> ≠ 0;
    $output ~= “ «exit signal = {Signal($_<signal>)} ($_<signal>)»” if .<signal> ≠ 0;
    $output
}

#↓ Substitutes some characters in $code if it looks like code, or
#↓ fetches code from a url if $code looks like one.
sub process-code($code is copy, $msg) is export {
    $code ~~ m{^ ( ‘http’ s? ‘://’ \S+ ) }
    ?? process-gist(~$0, $msg) // write-code process-url(~$0, $msg)
    !! write-code $code.subst: :g, ‘␤’, “\n”
}

#↓ Slurps contents of some page as if it was a raw link to code.
sub process-url($url, $msg) is export {
    my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
    my $response;
    try {
        $response = $ua.get: $url;
        CATCH {
            grumble ‘It looks like a URL, but for some reason I cannot download it’
                    ~ “ ({.message})”
        }
    }
    if not $response.is-success {
        grumble ‘It looks like a URL, but for some reason I cannot download it’
                ~ “ (HTTP status line is {$response.status-line})”
    }
    if not $response.content-type.contains: ‘text/plain’ | ‘perl’ {
        grumble “It looks like a URL, but mime type is ‘{$response.content-type}’”
                ~ ‘ while I was expecting something with ‘text/plain’ or ‘perl’’
                ~ ‘ in it. I can only understand raw links, sorry.’
    }

    my $body = $response.decoded-content;
    .reply: ‘Successfully fetched the code from the provided URL’ with $msg;
    sleep 0.02; # https://github.com/perl6/whateverable/issues/163
    $body
}

#↓ Handles github gists by placing the files into `sandbox/` directory.
#↓ Returns path to the main file (which was detected heuristically).
sub process-gist($url, $msg) is export {
    return unless $url ~~
      /^ ‘https://gist.github.com/’<[a..zA..Z-]>+‘/’(<.xdigit>**32) $/;

    my $gist-id = ~$0;
    my $api-url = ‘https://api.github.com/gists/’ ~ $gist-id;

    my $ua = HTTP::UserAgent.new: :useragent<Whateverable>;
    my $response;
    try {
        $response = $ua.get: $api-url;
        CATCH {
            grumble “Cannot fetch data from GitHub API ({.message})”
        }
    }
    if not $response.is-success {
        grumble ‘Cannot fetch data from GitHub API’
                ~ “ (HTTP status line is {$response.status-line})”
    }

    my %scores; # used to determine the main file to execute

    my %data = from-json $response.decoded-content;
    grumble ‘Refusing to handle truncated gist’ if %data<truncated>;

    sub path($filename) { “sandbox/$filename”.IO }

    for %data<files>.values {
        grumble ‘Invalid filename returned’ if .<filename>.contains: ‘/’|“\0”;

        my $score = 0; # for heuristics
        $score += 50 if .<language> && .<language> eq ‘Perl 6’;
        $score -= 20 if .<filename>.ends-with: ‘.pm6’;
        $score -= 10 if .<filename>.ends-with: ‘.t’;
        $score += 40 if !.<language> && .<content>.contains: ‘ MAIN’;

        my IO $path = path .<filename>;
        if .<size> ≥ 10_000_000 {
            $score -= 300;
            grumble ‘Refusing to handle files larger that 10 MB’;
        }
        if .<truncated> {
            $score -= 100;
            grumble ‘Can't handle truncated files yet’; # TODO?
        } else {
            spurt $path, .<content>;
        }
        %scores.push: .<filename> => $score
    }

    my $main-file = %scores.max(*.value).key;
    if $msg and %scores > 1 {
        $msg.reply: “Using file “$main-file” as a main file, other files are placed in “sandbox/””
    }
    path $main-file
}

# vim: expandtab shiftwidth=4 ft=perl6

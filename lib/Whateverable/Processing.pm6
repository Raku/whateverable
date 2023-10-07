# Copyright © 2016-2023
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
use Whateverable::Config;
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

#| Transform a revision into `output => short SHA` pair
sub process-commit($commit, $filename, :%ENV) is export {
    # convert to real ids so we can look up the builds
    my $full-commit = to-full-commit    $commit;
    my $short-commit = get-short-commit $commit;
    $short-commit ~= “({get-short-commit $full-commit})” if $commit eq ‘HEAD’;

    without $full-commit {
        return $short-commit R=> ‘Cannot find this revision (did you mean “’ ~
          get-short-commit(get-similar $commit, <HEAD v6.c releases all>) ~
          ‘”?)’
    }
    $short-commit R=> subprocess-commit $commit, $filename, $full-commit, :%ENV;
}

#| Runs process-commit on each commit and saves the
#| results in a given array and hash
sub proccess-and-group-commits(@outputs, # unlike %shas this is ordered
                               %shas,    # { output => [sha, sha, …], … }
                               $file,
                               *@commits,
                               :$intermingle=True, :$prepend=False,
                               :$start-time, :$time-limit,
                               :%ENV=%*ENV) is export {
    for @commits.map: { process-commit $_, $file, :%ENV } {
        if $start-time && $time-limit && now - $start-time > $time-limit { # bail out if needed
            grumble “«hit the total time limit of $time-limit seconds»”
        }
        my $push-needed = $intermingle
                          ?? (%shas{.key}:!exists)
                          !! !@outputs || @outputs.tail ne .key;
        @outputs.push: .key if $push-needed;
        if $prepend {
            %shas{.key}.prepend: .value;
        } else {
            %shas{.key}.append:  .value;
        }
    }
}

#| Takes the array and hash produced by `proccess-and-group-commits`
#| and turns it into a beautiful gist (or a short reply).
#| Note that it can list the same commit set more than once if you're
#| not using intermingle feature in proccess-and-group-commits.
#| Arguably it's a feature, but please judge yourself.
sub commit-groups-to-gisted-reply(@outputs, %shas, $config) is export {
    my $short-str = @outputs == 1 && %shas{@outputs[0]} > 3 && $config.chars < 20
    ?? “¦{$config} ({+%shas{@outputs[0]}} commits): «{@outputs[0]}»”
    !! ‘¦’ ~ @outputs.map({ “{%shas{$_}.join: ‘,’}: «$_»” }).join: ‘ ¦’;

    my $long-str  = ‘¦’ ~ @outputs.map({ “«{limited-join %shas{$_}}»:\n$_” }).join: “\n¦”;
    $short-str but ProperStr($long-str);
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
    sleep 0.02; # https://github.com/Raku/whateverable/issues/163
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

    sub path($filename) { “$CONFIG<sandbox-path>/$filename”.IO }

    for %data<files>.values {
        grumble ‘Invalid filename returned’ if .<filename>.contains: ‘/’|“\0”;

        my $score = 0; # for heuristics
        $score += 50 if .<language> && .<language> eq ‘Perl 6’;
        $score -= 20 if .<filename>.ends-with: ‘.pm6’;
        $score -= 10 if .<filename>.ends-with: ‘.t’;
        $score += 40 if .<content>.contains: ‘ MAIN’;

        my IO $path = path .<filename>;
        if .<size> ≥ 10_000_000 {
            $score -= 300;
            grumble ‘Refusing to handle files larger that 10 MB’;
        }
        if .<truncated> {
            $score -= 100;
            grumble ‘Can't handle truncated files yet’; # TODO?
        }

        mkdir $path.parent;
        spurt $path, .<content>;

        if .<filename>.ends-with: ‘.md’ | ‘.markdown’ {
            for ‘raku’, ‘perl6’, ‘perl’, ‘’ -> $type {
                if .<content> ~~ /‘```’ $type \s* \n ~ ‘```’ (.+?) / {
                    .<content> = ~$0;
                    #↓ XXX resave the file with just the code. Total hack but it works
                    spurt $path, .<content>;
                    $score += 3;
                    last
                }
            }
        }

        %scores.push: .<filename> => $score
    }

    my $main-file = %scores.max(*.value).key;
    if $msg and %scores > 1 {
        $msg.reply: “Using file “$main-file” as a main file, other files are placed in “$CONFIG<sandbox-path>””
    }
    path $main-file
}

# vim: expandtab shiftwidth=4 ft=perl6

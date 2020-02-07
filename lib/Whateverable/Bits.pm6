# Copyright © 2016-2020
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


# This file is a collection of tiny general purpose
# functions and other things.

role Helpful { method help($msg) { … } }

role Reply      { has $.msg              }
role ProperStr  { has $.long-str         }
role PrettyLink { has &.link-msg         }
role FileStore  { has %.additional-files }

sub shorten($str, $max, $cutoff=$max ÷ 2) is export {
    $max ≥ $str.chars ?? $str !! $str.substr(0, $cutoff - 1) ~ ‘…’
}

sub fuzzy-nick($nick, $distance) is export {
    use Text::Diff::Sift4;
    / \w+ <?{ sift4(~$/, $nick, 5) ~~ 1..$distance }> /
}

sub signal-to-text($signal) is export {
    “$signal ({$signal ?? Signal($signal) !! ‘None’})”
}

sub s($count, $word) is export {
    +$count ~ ‘ ’ ~ $word ~ ($count == 1 ?? ‘’ !! ‘s’)
}

sub maybe($format, $string) is export {
    $string ?? $string.fmt: $format !! ‘’
}

sub markdown-escape($text) is export {
    # TODO is it correct? No, that's an ugly hack…
    $text.trans: (｢<｣,   ｢>｣,  ｢&｣,  ｢\｣,  ｢`｣,  ｢*｣,  ｢_｣,  ｢~｣,  ｢|｣) =>
                 (｢\<｣, ｢\>｣, ｢\&｣, ｢\\｣, ｢\`｣, ｢\*｣, ｢\_｣, ｢\~｣, ｢\|｣); # ｣);
}

sub html-escape($text) is export {
    $text.trans: (‘&’, ‘<’, ‘>’) => (‘&amp;’, ‘&lt;’, ‘&gt;’)
}

my token irc-nick is export {
    [
        | <[a..zA..Z0..9]>
        | ‘-’ | ‘_’ | ‘[’ | ‘]’ | ‘{’ | ‘}’ | ‘\\’ | ‘`’ | ‘|’
    ]+
}

my token commit-list is export {
    [<-[\s] -[‘,’]>+]+ % [‘,’\s*]
}

#| Get the closest fuzzy match
sub did-you-mean($string, @options, :$default=Nil,
                 :$max-offset=7, :$max-distance=10) is export {
    my $answer = $default;
    my $answer-min = ∞;
    my $distance-limit = $max-distance + 1;
    $distance-limit = 17 if $distance-limit < 17;

    use Text::Diff::Sift4;
    for @options {
        my $distance = sift4 $_, $string, $max-offset, $distance-limit;
        if $distance < $answer-min {
            $answer = $_;
            $answer-min = $distance;
        }
    }
    return $default if $answer-min > $max-distance;
    $answer
}

sub time-left(Instant() $then, :$already-there?) is export {
    my $time-left = $then - now;
    return $already-there if $already-there and $time-left < 0;
    my ($seconds, $minutes, $hours, $days) = $time-left.polymod: 60, 60, 24;
    if not $days and not $hours {
        return ‘is just a few moments away’ unless $minutes;
        return “is in $minutes minute{‘s’ unless $minutes == 1}”;
    }
    my $answer = ‘in ’;
    $answer ~= “$days day{$days ≠ 1 ?? ‘s’ !! ‘’} and ” if $days;
    $answer ~= “≈$hours hour{$hours ≠ 1 ?? ‘s’ !! ‘’}”;
    $answer
}

#| Get current timestamp (DateTime)
sub timestampish is export { DateTime.now(:0timezone).truncated-to: ‘seconds’ }

#↓ Spurt into a tempfile.
sub write-code($code --> IO) is export {
    use File::Temp;
    my ($filename, $filehandle) = tempfile :!unlink;
    $filehandle.print: $code;
    $filehandle.close;
    $filename.IO
}

#| Use Cro to fetch from a URL (like GitHub API)
sub curl($url, :@headers) is export {
    use Cro::HTTP::Client;
    use Whateverable::Config;
    my @new-headers = @headers;
    @new-headers.push: (User-Agent => ‘Whateverable’);
    if $url.starts-with: ‘https://api.github.com/’ and $CONFIG<github><access_token> {
        @new-headers.push: (Authorization => ‘token ’ ~ $CONFIG<github><access_token>);
    }
    my Cro::HTTP::Client $client .= new: headers => @new-headers;
    my $resp = await $client.get: $url;
    my $return = await $resp.body;

    # Extra stuff in case you need it
    # Next url
    my $next = $resp.headers.first(*.name eq ‘Link’).?value;
    if $next && $next ~~ /‘<’ (<-[>]>*?) ‘>; rel="next"’/ {
        my $next-url = ~$0;
        role NextURL { has $.next-url };
        $return = $return but NextURL($next-url);
    }
    # Rate limiting
    my $rate-limit       = $resp.headers.first(*.name eq ‘X-RateLimit-Remaining’).?value;
    my $rate-limit-reset = $resp.headers.first(*.name eq ‘X-RateLimit-Reset’).?value;
    $rate-limit-reset -= time; # time to sleep instead of when to wake up
    if $rate-limit.defined and $rate-limit < 5 {
        role RateLimited { has $.rate-limit-reset-in }
        $return = $return but RateLimited($rate-limit-reset);
    }

    $return
}

# Exceptions
class Whateverable::X::HandleableAdHoc is X::AdHoc is export {}

sub grumble(|c) is export {
    Whateverable::X::HandleableAdHoc.new(payload => c).throw
}

# vim: expandtab shiftwidth=4 ft=perl6

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

use IRC::Client;
use Whateverable::Bits;
use Whateverable::Config;

unit module Whateverable::Messages;

role Enough is export { } #← Used to prevent recursion in exception handling

sub handle-exception($exception, $msg?) is export {
    CATCH { # exception handling is too fat, so let's do this also…
        .note;
        return ‘Exception was thrown while I was trying to handle another exception…’
             ~ ‘ What are they gonna do to me, Sarge? What are they gonna do⁈’
    }
    if $exception ~~ Whateverable::X::HandleableAdHoc { # oh, it's OK!
        return $exception.message but Reply($_) with $msg;
        return $exception.message
    }

    note $exception;
    given $msg {
        # TODO handle other types
        when IRC::Client::Message::Privmsg::Channel {
            .irc.send-cmd: ‘PRIVMSG’, $CONFIG<cave>, “I'm acting stupid on {.channel}. Help me.”,
                           :server(.server), :prefix($CONFIG<caregivers>.join(‘, ’) ~ ‘: ’)
                if .channel ne $CONFIG<cave>
        }
        default {
            .irc.send-cmd: ‘PRIVMSG’, $CONFIG<cave>, ‘Unhandled exception somewhere!’,
                           :server(.server), :prefix($CONFIG<caregivers>.join(‘, ’) ~ ‘: ’);
        }
    }

    my ($text, @files) = flat awesomify-exception $exception;
    @files .= map({ ‘uncommitted-’ ~ .split(‘/’).tail => .IO.slurp });
    @files.push: ‘|git-diff-HEAD.patch’ => run(:out, <git diff HEAD>).out.slurp-rest if @files;
    @files.push: ‘result.md’ => $text;

    my $return = (‘’ but FileStore(%@files))
      but PrettyLink({“No! It wasn't me! It was the one-armed man! Backtrace: $_”});
    # https://youtu.be/MC6bzR9qmxM?t=97
    $return = $return but Reply($_) with $msg;
    if $msg !~~ IRC::Client::Message::Privmsg::Channel {
        $msg.irc.send-cmd: ‘PRIVMSG’, $CONFIG<cave>, $return but Enough,
                           :server($msg.server),
                           :prefix($CONFIG<caregivers>.join(‘, ’) ~ ‘: ’);
        return
    }
    $return
}

sub awesomify-exception($exception) {
    my @local-files;
    my $sha = run(:out, <git rev-parse --verify HEAD>).out.slurp-rest;
    ‘<pre>’ ~
    $exception.gist.lines.map({
        # TODO Proper way to get data out of exceptions?
        # For example, right now it is broken for paths with spaces
        when /:s ^([\s**2|\s**6]in \w+ \S* at “./”?)$<path>=[\S+](
                                         [<.ws>‘(’<-[)]>+‘)’]? line )$<line>=[\d+]$/ {
            my $status = run :out, <git status --porcelain --untracked-files=no -->,
                                   ~$<path>;
            proceed if !$status && !%*ENV<DEBUGGABLE>; # not a repo file and not in the debug mode
            my $private-debugging = !$status;
            $status = $status.out.slurp-rest;
            my $uncommitted = $status && !$status.starts-with: ‘  ’; # not committed yet
            @local-files.push: ~$<path> if $uncommitted || $private-debugging;
            my $href = $uncommitted || $private-debugging
              ?? “#file-uncommitted-{$<path>.split(‘/’).tail.lc.trans(‘.’ => ‘-’)}-” # TODO not perfect but good enough
              !! “$CONFIG<source>/blob/$sha/{markdown-escape $<path>}#”;
            $href ~= “L$<line>”;

            markdown-escape($0) ~
            # let's hope for the best ↓
            “<a href="$href">{$<path>}</a>” ~
            markdown-escape($1 ~ $<line>) ~
            ($uncommitted ?? ‘ (⚠ uncommitted)’ !! ‘’)
        }
        default { $_ }
    }).join(“\n”)
    ~ ‘</pre>’, @local-files
}

# vim: expandtab shiftwidth=4 ft=perl6

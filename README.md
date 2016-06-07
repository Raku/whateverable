# bisectbot
IRC bot for a lightning fast git bisect

This bot runs as ``bisectable`` on ``#perl6``.
Currently ``AlexDaniel`` is maintaining it.

## Usage examples
```
<AlexDaniel> bisect: exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT 128181
<bisectable> AlexDaniel: (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120ca
```

Garbage in, rainbows out. Attempts to guess what you have meant:
```
<AlexDaniel> say (^∞).grep({ last })[5] # same but without proper exit codes
<bisectable> AlexDaniel: exit code is 0 on both starting points, bisecting by using the output
<bisectable> AlexDaniel: (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120ca
```

```
<AlexDaniel> bisect: class A { has $.wut = [] }; my $a = A.new; $a.wut = [1,2,3]
<bisectable> AlexDaniel: exit code on a “good” revision is 1 (which is bad), bisecting with inverted logic
<bisectable> AlexDaniel: (2016-03-02) https://github.com/rakudo/rakudo/commit/fdd37a9
```

```
<AlexDaniel> bisect: exit 42
<bisectable> AlexDaniel: on both starting points the exit code is 42 and the output is identical as well
```

More examples:
```
<moritz> bisect: try { NaN.Rat == NaN; exit 0 }; exit 1
<bisectable> moritz: (2016-05-02) https://github.com/rakudo/rakudo/commit/e2f1fa7
```

```
<AlexDaniel> bisect: for ‘q b c d’.words -> $a, $b { }; CATCH { exit 0 }; exit 1
<bisectable> AlexDaniel: (2016-03-01) https://github.com/rakudo/rakudo/commit/1b6c901
```

```
<AlexDaniel> bisectable: help
<bisectable> AlexDaniel: Like this: bisect: good=2015.12 bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT 128181
```

```
<AlexDaniel> bisect: good=2016.03 bad 2016.02 say (^∞).grep({ last })[5] # swapped good and bad revisions
<bisectable> AlexDaniel: exit code is 0 on both starting points, bisecting by using the output
<bisectable> AlexDaniel: “bisect run” failure
```

Defaults to ``good=2015.12`` and ``bad=HEAD``.

## Installation
Run ``new-commits`` script periodically to process new commits.
Basically, that's it.

Some of these scripts are sensitive to the current working directory.
Use with care.

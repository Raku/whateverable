# bisectbot
IRC bot for a lightning fast git bisect

This bot runs as ``bisectable`` on ``#perl6``.
Currently ``AlexDaniel`` is maintaining it.

## Usage examples

```
<AlexDaniel> bisect: exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT 128181
<bisectable> AlexDaniel: (2016-03-18) https://github.com/rakudo/rakudo/commit/6d120ca
```

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
<bisectable> AlexDaniel: Like this: bisect: good=v6.c bad=HEAD exit 1 if (^∞).grep({ last })[5] // 0 == 4 # RT 128181
```

Defaults to ``good=v6.c`` and ``bad=HEAD``.

Garbage in, garbage out. Currently does not check if your code snippet results
in a different output on starting points.

## Installation
Run ``new-commits`` script periodically to process new commits.
Basically, that's it.

Some of these scripts are sensitive to the current working directory.
Use with care.

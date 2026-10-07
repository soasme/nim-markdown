import std/assertions

import markdownpkg/regexcompat as regexcompat

block anchoredMatchKeepsGreedyCaptures:
  var captures: array[1, string]
  let pattern = regexcompat.re("(a+)")
  doAssert regexcompat.matchLen("aaaab", pattern, captures) == 4
  doAssert captures[0] == "aaaa"

block boundedMatchTreatsLimitAsTheEndOfInput:
  let pattern = regexcompat.re("\\n$")
  doAssert regexcompat.matchLen("xx\nmore", pattern, 2, 3) == 1

block boundedMatchKeepsAbsoluteCaptureOffsets:
  var captures: array[1, string]
  let pattern = regexcompat.re("(foo)")
  doAssert regexcompat.matchLen("xxfoo!", pattern, captures, 2, 5) == 3
  doAssert captures[0] == "foo"

block boundedLookaheadTreatsLimitAsTheEndOfInput:
  let pattern = regexcompat.re("foo(?=$)")
  doAssert regexcompat.matchLen("xxfoo!", pattern, 2, 5) == 3

block caretUsesTheOriginalInputStart:
  let pattern = regexcompat.re("^foo")
  doAssert regexcompat.matchLen("xxfoo", pattern, 2) == -1

block wordBoundaryUsesTheOriginalInputContext:
  let pattern = regexcompat.re("\\bfoo")
  doAssert regexcompat.matchLen("xfoo", pattern, 1) == -1

block lookbehindUsesTheOriginalInputContext:
  let pattern = regexcompat.re("(?<=x)foo")
  doAssert regexcompat.matchLen("xfoo", pattern, 1) == 3

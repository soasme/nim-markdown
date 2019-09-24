import unittest
import strutils, sequtils, strscans, system, os
import markdown

type
  IncludeParser = ref object of Parser

  IncludeToken = ref object of Block
    path: string

var c = initCommonmarkConfig()
c.blockParsers.insert(IncludeParser(), 0)

method parse(parser: IncludeParser, doc: string, start: int): ParseResult  {.locks: "unknown".}=
  var idx = start
  var path = ""

  if scanp(
    doc, idx,
    (
      "#include",
      +{' ', '\t'},
      '"',
      +( ~{'"', '\n'} -> path.add($_)),
      '"',
      *{' ', '\n'},
    )
  ):
    ParseResult(token: IncludeToken(path: path), pos: idx)
  else:
    ParseResult(token: nil, pos: -1)

method `$`(token: IncludeToken): string =
  markdown(token.path.readFile, c)


test "customize parsing":
  writeFile("hello.md", "# I'm included.")
  let md = """
#include nothing

#include "hello.md"
"""
  check markdown(md, c) == """<p>#include nothing</p>
<h1>I'm included.</h1>

"""
  removeFile("hello.md")

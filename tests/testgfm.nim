import unittest

import re, strutils, os, json, strformat
import markdown

let KNOW_ISSUES = [
  334, # *foo`*`: backtick should have higher precedence than emphasis.
  335, # [not a `link](/foo`): backtick should have higher precedence than inline link.
  339, # <http://foo.bar.`baz>`: backtick should be escaped in autolink.
  340, #```foo``: When a backtick string is not closed by a matching backtick string, we just have literal backticks
]

test "gfm":
  for gfmCase in parseFile("./tests/gfm-spec.json").items:
    var exampleId: int = gfmCase["id"].getInt
    var caseName = fmt"gfm example {exampleId}"
    test caseName:
      if KNOW_ISSUES.contains(exampleId):
        skip
      else:
        check markdown(gfmCase["md"].getStr) == gfmCase["html"].getStr

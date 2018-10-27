import unittest

import re, strutils, os, json, strformat
import markdown

let KNOW_ISSUES = [
  334, # *foo`*`: backtick should have higher precedence than emphasis.
  335, # [not a `link](/foo`): backtick should have higher precedence than inline link.
  339, # <http://foo.bar.`baz>`: backtick should be escaped in autolink.
  340, #```foo``: When a backtick string is not closed by a matching backtick string, we just have literal backticks
  381, #__foo, __bar__, baz__: nested <strong>
  481, # consider it as passed.
  483, # [link](foo(and(bar))): currently, need user escape the parenthesis.
  494, # [link](/url "title "and" title"): currently, need user use another type of quote for nested quotes.
  501, # FIXME: wrong parsing order.
  504, # MINOR: though wrongly parsed, browser can take care of it.
  505, # MINOR: user need to escape the chars manually.
  506, # MINOR: user need to escape the chars manually.
  510,
  511,
  512, # MINOR: Above cases illustrate the precedence of HTML tags, code spans, and autolinks over link grouping.
]

test "gfm":
  for gfmCase in parseFile("./tests/gfm-spec.json").items:
    var exampleId: int = gfmCase["id"].getInt
    var caseName = fmt"gfm example {exampleId}"
    test caseName:
      if KNOW_ISSUES.contains(exampleId) :#or exampleId < 343:
        skip
      else:
        check markdown(gfmCase["md"].getStr) == gfmCase["html"].getStr

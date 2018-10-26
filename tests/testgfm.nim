import unittest

import re, strutils, os, json, strformat
import markdown

test "gfm":
  for gfmCase in parseFile("./tests/gfm-spec.json").items:
    var exampleId: int = gfmCase["id"].getInt
    var caseName = fmt"gfm example {exampleId}"
    test caseName:
      check markdown(gfmCase["md"].getStr) == gfmCase["html"].getStr

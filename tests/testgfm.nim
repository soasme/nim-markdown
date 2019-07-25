import re, strutils, os, json, strformat, unittest

import markdown

for gfmCase in parseFile("./tests/gfm-spec.json").getElems:
  var exampleId: int = gfmCase["example"].getInt
  var caseName = fmt"gfm example {exampleId}"
  var md = getStr(gfmCase["markdown"])
  test fmt"{exampleId}":
    check markdown(md) == gfmCase["html"].getStr

import re, strutils, os, json, strformat, unittest

import markdown

for cmarkCase in parseFile("./tests/commonmark-spec-0.29.json").getElems:
  var exampleId: int = cmarkCase["example"].getInt
  var caseName = fmt"cmark example {exampleId}"
  var md = getStr(cmarkCase["markdown"])
  test fmt"{exampleId}":
    check markdown(md) == cmarkCase["html"].getStr

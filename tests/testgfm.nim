from unittest import check

import re, strutils, os, json, strformat

import markdown

for gfmCase in parseFile("./tests/gfm-spec.json").getElems:
  var exampleId: int = gfmCase["id"].getInt
  var caseName = fmt"gfm example {exampleId}"
  var md = getStr(gfmCase["md"])
  echo(exampleId)
  check markdown(md) == gfmCase["html"].getStr
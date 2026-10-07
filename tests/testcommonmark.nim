import strutils, os, json, strformat, unittest

import markdown

proc withoutHeadingIds(html: string): string =
  result = html
  for tag in ["h1", "h2"]:
    let prefix = "<" & tag & " id=\""
    var start = result.find(prefix)
    while start != -1:
      let idEnd = result.find('"', start + prefix.len)
      if idEnd == -1:
        break
      result = result[0 ..< start + tag.len + 1] & result[idEnd + 1 .. ^1]
      start = result.find(prefix, start + tag.len + 2)

for cmarkCase in parseFile("./tests/commonmark-spec-0.29.json").getElems:
  var exampleId: int = cmarkCase["example"].getInt
  var caseName = fmt"cmark example {exampleId}"
  var md = getStr(cmarkCase["markdown"])
  test fmt"{exampleId}":
    # Heading IDs are an intentional extension and are not present in the
    # CommonMark fixtures.
    check markdown(md).withoutHeadingIds == cmarkCase["html"].getStr

# To run these tests, simply execute `nimble test`.
# If you have `watchdog`(pip install watchdog), you can run `make test` to watch testing while

import unittest

import re, strutils, os, json, strformat, sequtils
import markdown

const
  config = initMarkdownConfig()
  configNoEscape = initMarkdownConfig(escape = false)

test "newline":
  check markdown("\n\n\n") == ""

test "indented block code":
  check markdown("    proc helloworld():\n") == "<pre><code>proc helloworld():\n</code></pre>\n"
  check markdown("    proc helloworld():\n        echo(\"hello world\")\n"
    ) == "<pre><code>proc helloworld():\n    echo(&quot;hello world&quot;)\n</code></pre>\n"

test "fencing block code":
  check markdown("```nim\nproc helloworld():\n  echo(\"hello world\")\n```"
    ) == "<pre><code class=\"language-nim\">proc helloworld():\n  echo(&quot;hello world&quot;)\n</code></pre>\n"
  check markdown("```\nproc helloworld():\n  echo(\"hello world\")\n```"
    ) == "<pre><code>proc helloworld():\n  echo(&quot;hello world&quot;)\n</code></pre>\n"

test "paragraph":
  check markdown("hello world") == "<p>hello world</p>\n"
  check markdown("p1\np2\n") == "<p>p1\np2</p>\n"
  check markdown("p1\n") == "<p>p1</p>\n"
  check markdown("p1\n\np2\n") == "<p>p1</p>\n<p>p2</p>\n"

test "bulleted item list":
  check markdown("* a\n* b\n") == """<ul>
<li>a</li>
<li>b</li>
</ul>
"""
  check markdown("* a\n * b\n* c") == """<ul>
<li>a</li>
<li>b</li>
<li>c</li>
</ul>
"""
  check markdown("+ a\n+ b\n") == """<ul>
<li>a</li>
<li>b</li>
</ul>
"""
  check markdown("- a\n- b\n") == """<ul>
<li>a</li>
<li>b</li>
</ul>
"""
  check markdown("1. a\n2. b\n") == """<ol>
<li>a</li>
<li>b</li>
</ol>
"""
  check markdown("1. a\n* b\n") == """<ol>
<li>a</li>
</ol>
<ul>
<li>b</li>
</ul>
"""

test "define link":
  check markdown("[1]: https://example.com") == ""

test "html block":
  check markdown("<hr>\n\n") == "<hr>\n"
  check markdown("<!-- comment -->\n\n") == "<!-- comment -->\n"
  check markdown("<strong>hello world</strong>\n\n") == "<p><strong>hello world</strong></p>\n"
  check markdown("<strong class='special'>hello world</strong>\n\n") == "<p><strong class='special'>hello world</strong></p>\n"
  check markdown("<strong class=\"special\">hello world</strong>\n\n") == "<p><strong class=\"special\">hello world</strong></p>\n"

test "html block: default keeping":
  check markdown("<hr>\n\n") == "<hr>\n"
  check markdown("<!-- comment -->\n\n") == "<!-- comment -->\n"
  check markdown("<strong>hello world</strong>\n\n") == "<p><strong>hello world</strong></p>\n"
  check markdown("<strong class='special'>hello world</strong>\n\n") == "<p><strong class='special'>hello world</strong></p>\n"
  check markdown("<strong class=\"special\">hello world</strong>\n\n") == "<p><strong class=\"special\">hello world</strong></p>\n"

test "inline autolink":
  check markdown("email to <test@example.com>") == "<p>email to <a href=\"mailto:test@example.com\">test@example.com</a></p>\n"
  check markdown("go to <https://example.com>") == "<p>go to <a href=\"https://example.com\">https://example.com</a></p>\n"
  check markdown("go to <http://example.com>") == "<p>go to <a href=\"http://example.com\">http://example.com</a></p>\n"

test "inline escape":
  check markdown("""\<p\>""") == "<p>&lt;p&gt;</p>\n"

test "inline html":
  check markdown("hello <em>world</em>") == "<p>hello <em>world</em></p>\n"

test "inline link":
  check markdown("[test](https://example.com)") == "<p><a href=\"https://example.com\">test</a></p>\n"
  check markdown("[test](<https://example.com>)") == "<p><a href=\"https://example.com\">test</a></p>\n"
  check markdown("[test](<https://example.com> 'hello')") == "<p><a href=\"https://example.com\" title=\"hello\">test</a></p>\n"
  check markdown("[test](<https://example.com> \"hello\")") == "<p><a href=\"https://example.com\" title=\"hello\">test</a></p>\n"
  check markdown("![test](https://example.com)") == "<p><img src=\"https://example.com\" alt=\"test\" /></p>\n"

test "inline reflink":
  check markdown("[Example][test]\n\n[test]: https://example.com"
    ) == "<p><a href=\"https://example.com\">Example</a></p>\n"
  check markdown("[test]  [Example]\n\n[test]: https://example.com"
    ) == "<p><a href=\"https://example.com\">test</a>  [Example]</p>\n"

test "inline nolink":
  check markdown("[test]\n\n[test]: https://example.com"
    ) == "<p><a href=\"https://example.com\">test</a></p>\n"
  check markdown("[test]\n\n[test]: https://example.com \"TEST\""
    ) == "<p><a href=\"https://example.com\" title=\"TEST\">test</a></p>\n"


# test "inline url":
#   check markdown("https://example.com"
#     ) == """<p><a href="https://example.com">https://example.com</a></p>
# """

test "inline double emphasis":
  check markdown("**a**") == "<p><strong>a</strong></p>\n"
  check markdown("__a__") == "<p><strong>a</strong></p>\n"

test "inline emphasis":
  check markdown("*a*") == "<p><em>a</em></p>\n"
  check markdown("_a_") == "<p><em>a</em></p>\n"
  check markdown("*a* **b** ***c***") == "<p><em>a</em> <strong>b</strong> <em><strong>c</strong></em></p>\n"

test "inline code":
  check markdown("`code`") == "<p><code>code</code></p>\n"
  check markdown("``code``") == "<p><code>code</code></p>\n"
  check markdown("```code```") == "<p><code>code</code></p>\n"

test "inline break":
  check markdown("hello\nworld") == "<p>hello\nworld</p>\n"
  check markdown("hello\\\nworld") == "<p>hello<br />\nworld</p>\n"
  check markdown("hello  \nworld") == "<p>hello<br />\nworld</p>\n"

test "inline strikethrough":
  check markdown("~~hello~~") == "<p><del>hello</del></p>\n"

test "escape \\":
  check markdown("1 < 2") == "<p>1 &lt; 2</p>\n"

test "table":
  check markdown("""
| Header 1 | Header 2 | Header 3 | Header 4 |
| :------: | -------: | :------- | -------- |
| Cell 1   | Cell 2   | Cell 3   | Cell 4   |
| Cell 5   | Cell 6   | Cell 7   | Cell 8   |
  """
  ) == """<table>
<thead>
<tr>
<th align="center">Header 1</th>
<th align="right">Header 2</th>
<th align="left">Header 3</th>
<th>Header 4</th>
</tr>
</thead>
<tbody>
<tr>
<td align="center">Cell 1</td>
<td align="right">Cell 2</td>
<td align="left">Cell 3</td>
<td>Cell 4</td>
</tr>
<tr>
<td align="center">Cell 5</td>
<td align="right">Cell 6</td>
<td align="left">Cell 7</td>
<td>Cell 8</td>
</tr></tbody></table>
"""

  check markdown("""
| Header 1 | Header 2
| -------- | --------
| Cell 1   | Cell 2
| Cell 3   | Cell 4"""
  ) == """<table>
<thead>
<tr>
<th>Header 1</th>
<th>Header 2</th>
</tr>
</thead>
<tbody>
<tr>
<td>Cell 1</td>
<td>Cell 2</td>
</tr>
<tr>
<td>Cell 3</td>
<td>Cell 4</td>
</tr></tbody></table>
"""

test "list & inline link":
  check markdown("""
1. [foo](https://nim-lang.org)
2. [bar](https://nim-lang.org/installation)


- [foo](https://nim-lang.org)
- [bar](https://nim-lang.org/installation)
""") == """
<ol>
<li><a href="https://nim-lang.org">foo</a></li>
<li><a href="https://nim-lang.org/installation">bar</a></li>
</ol>
<ul>
<li><a href="https://nim-lang.org">foo</a></li>
<li><a href="https://nim-lang.org/installation">bar</a></li>
</ul>
"""
check markdown("""
1. [foo](https://nim-lang.org)
2. [bar](https://nim-lang.org/installation)
- [foo](https://nim-lang.org)
- [bar](https://nim-lang.org/installation)
""") == """
<ol>
<li><a href="https://nim-lang.org">foo</a></li>
<li><a href="https://nim-lang.org/installation">bar</a></li>
</ol>
<ul>
<li><a href="https://nim-lang.org">foo</a></li>
<li><a href="https://nim-lang.org/installation">bar</a></li>
</ul>
"""

test "get link test":
  var slice: Slice[int]
  check getLinkText("[a]", 0, slice) == 3; check slice == (0 .. 2)
  check getLinkText("[[a]", 0, slice) == -1;
  check getLinkText("[[a]", 1, slice) == 3; check slice == (1 .. 3)
  check getLinkText("[[a]]", 0, slice) == 5; check slice == (0 .. 4)
  check getLinkText("[a]]", 0, slice) == 3; check slice == (0 .. 2)
  check getLinkText(r"[a\]]", 0, slice) == 5; check slice == (0 .. 4)
  check getLinkText("[link]", 0, slice) == 6; check slice == (0 .. 5)
  check getLinkText("[link [foo [bar]]]", 0, slice) == 18; check slice == (0 .. 17)
  check getLinkText("[link] bar]", 0, slice) == 6; check slice == (0 .. 5)
  check getLinkText("[link [bar]", 0, slice) == -1;
  check getLinkText(r"[link \[bar]", 0, slice) == 12; check slice == (0 .. 11)
  check getLinkText("[foo [bar](/uri)]", 0, slice) == -1
  check getLinkText("[foo *[bar [baz](/uri)](/uri)*]", 0, slice) == -1
  check getLinkText("![[[foo](uri1)](uri2)]", 1, slice, allowNested=true) == 21; check slice == (1 .. 21)
  check getLinkText("*[foo*]", 1, slice) == 6; check slice == (1 .. 6)
  check getLinkText("[foo`]`", 0, slice) == -1;
  check getLinkText("[foo`]`]", 0, slice) == 8; check slice == (0 .. 7);
  check getLinkText("[foo <a href=]>]", 0, slice) == 16; check slice == (0 .. 15);
  check getLinkText("[[foo](/uri)]", 0, slice) == -1
  check getLinkText("[![foo](/uri)]", 0, slice) == 14; check slice == (0 .. 13)

test "get link destination":
  var doc = ""
  var slice: Slice[int]

  doc = "(<a>)"; check getLinkDestination(doc, 1, slice) == 3; check doc[slice] == "a"
  doc = "(/uri)";  check getLinkDestination(doc, 1, slice) == 4; check doc[slice] == "/uri"
  doc = "(/uri \"title\")";  check getLinkDestination(doc, 1, slice) == 4; check doc[slice] == "/uri"
  doc = "()";  check getLinkDestination(doc, 1, slice) == 0; check doc[slice] == ""
  doc = "(<>)";  check getLinkDestination(doc, 1, slice) == 2; check doc[slice] == ""
  doc = "(/my uri)";  check getLinkDestination(doc, 1, slice) == 3; check doc[slice] == "/my" # we'll abort at link title step
  doc = "(</my uri>)";  check getLinkDestination(doc, 1, slice) == 9; check doc[slice] == "/my uri"
  doc = "(foo\nbar)"; check getLinkDestination(doc, 1, slice) == 3; # we'll abort at link title step
  doc = "(<foo\nbar>)"; check getLinkDestination(doc, 1, slice) == -1;
  doc = r"(\(foo\))";  check getLinkDestination(doc, 1, slice) == 7; check doc[slice] == r"\(foo\)"
  doc = r"(foo(and(bar)))";  check getLinkDestination(doc, 1, slice) == 13; check doc[slice] == r"foo(and(bar))"
  doc = r"(foo\(and\(bar\))";  check getLinkDestination(doc, 1, slice) == 15; check doc[slice] == r"foo\(and\(bar\)"
  doc = r"(<foo(and(bar)>)";  check getLinkDestination(doc, 1, slice) == 14; check doc[slice] == r"foo(and(bar)"
  doc = r"(foo\)\:)";  check getLinkDestination(doc, 1, slice) == 7; check doc[slice] == r"foo\)\:"
  doc = r"(#fragment)";  check getLinkDestination(doc, 1, slice) == 9; check doc[slice] == r"#fragment"
  doc = "(\"title\")";   check getLinkDestination(doc, 1, slice) == 7; check doc[slice] == "\"title\""
  doc = "(   /uri\n  \"title\""; check getLinkDestination(doc, 4, slice) == 4; check doc[slice] == "/uri"

test "get link title":
  var slice: Slice[int]
  check getLinkTitle("/url \"title\"", 5, slice) == 7; check "/url \"title\""[slice] == "title"
  check getLinkTitle("/url 'title'", 5, slice) == 7; check "/url 'title'"[slice] == "title"
  check getLinkTitle("/url (title)", 5, slice) == 7; check "/url (title)"[slice] == "title"

test "get link label":
  var label = ""
  check getLinkLabel("[a]", 0, label) == 3; check label == "a"
  check getLinkLabel("[a]]", 0, label) == 3; check label == "a"
  check getLinkLabel("[a[]", 0, label) == -1

test "parse code fence":
  var codeIndent = 0
  var fenceSize = -1
  check parseFencedCode("`", codeIndent, fenceSize) == ""
  check parseFencedCode("~", codeIndent, fenceSize) == ""
  check parseFencedCode("``", codeIndent, fenceSize) == ""
  check parseFencedCode("~~", codeIndent, fenceSize) == ""
  check parseFencedCode("```", codeIndent, fenceSize) == "```"
  check parseFencedCode("~~~", codeIndent, fenceSize) == "~~~"
  check parseFencedCode("````", codeIndent, fenceSize) == "````"
  check parseFencedCode("~~~~", codeIndent, fenceSize) == "~~~~"
  check parseFencedCode("````", codeIndent, fenceSize) == "````"
  check parseFencedCode("~~~~", codeIndent, fenceSize) == "~~~~"
  check parseFencedCode("   ```", codeIndent, fenceSize) == "```"
  check codeIndent == 3

test "parse code info":
  var codeSize = -1
  check parseCodeInfo("", codeSize) == ""
  check codeSize == 0
  check parseCodeInfo("nim", codeSize) == "nim"
  check codeSize == 3
  check parseCodeInfo("nim\n", codeSize) == "nim"
  check codeSize == 4
  check parseCodeInfo("nim`", codeSize) == ""
  check codeSize == -1
  check parseCodeInfo(";", codeSize) == ";"
  check codeSize == 1
  check parseCodeInfo("    ruby startline=3 $%@#$\n", codeSize) == "ruby"
  check codeSize == 27

test "parse code content":
  var codeContent = ""
  check parseCodeContent("a\n```", 0, "```", codeContent) == 5
  check codeContent == "a\n"
  codeContent = ""
  check parseCodeContent(" a\n```", 1, "```", codeContent) == 6
  check codeContent == "a\n"
  codeContent = "" # 88
  check parseCodeContent("<\n >\n```", 0, "```", codeContent) == 8
  check codeContent == "<\n >\n"
  codeContent = "" # 89
  check parseCodeContent("<\n >\n~~~", 0, "~~~", codeContent) == 8
  check codeContent == "<\n >\n"
  codeContent = "" # 91
  check parseCodeContent("a\n~~~\n```", 0, "```", codeContent) == 9
  check codeContent == "a\n~~~\n"
  codeContent = "" # 92
  check parseCodeContent("a\n```\n~~~", 0, "~~~", codeContent) == 9
  check codeContent == "a\n```\n"
  codeContent = "" # 93
  check parseCodeContent("a\n```\n`````", 0, "````", codeContent) == 11
  check codeContent == "a\n```\n"
  codeContent = "" # 94
  check parseCodeContent("a\n~~~\n~~~~", 0, "~~~~", codeContent) == 10
  check codeContent == "a\n~~~\n"
  codeContent = "" # 96
  check parseCodeContent("\n\n```\na", 0, "`````", codeContent) == 7
  check codeContent == "\n\n```\na"
  check parseCodeContent(" a\na\n```", 1, "```", codeContent) == 8
  check codeContent == "a\na\n"
  codeContent = "" # 101
  check parseCodeContent("   a\n    a\n  a\n   ```", 3, "```", codeContent) == 21
  check codeContent == "a\n a\na\n"

test "parse html content":
  var htmlContent = ""
  check parseHTMLBlockContent("<script>console.log('hello')</script>", HTML_SCRIPT_START, HTML_SCRIPT_END, htmlContent) == 37
  check htmlContent == "<script>console.log('hello')</script>"

  check parseHTMLBlockContent("<script>\nconsole.log('hello')\n</script>", HTML_SCRIPT_START, HTML_SCRIPT_END, htmlContent) == 39
  check htmlContent == "<script>\nconsole.log('hello')\n</script>"

  # 116
  check parseHTMLBlockContent("<table><tr><td>\n<pre>\n**hello**\n\n_world_.</pre>", HTML_TAG_START, HTML_TAG_END, htmlContent) == 33
  check htmlContent == "<table><tr><td>\n<pre>\n**hello**\n\n"

  # Example 117
  check parseHTMLBlockContent("<table>\n <tr> \n      <td>hi</td>\n </tr>\n</table>\n\n okay.", HTML_TAG_START, HTML_TAG_END, htmlContent) == 50
  check htmlContent == "<table>\n <tr> \n      <td>hi</td>\n </tr>\n</table>\n\n"

  # 118
  check parseHTMLBlockContent(" <div>\n  *hello*\n           <foo><a>", HTML_TAG_START, HTML_TAG_END, htmlContent) == 36
  check htmlContent == " <div>\n  *hello*\n           <foo><a>"

  # 119
  check parseHTMLBlockContent("</div>\n*foo*", HTML_TAG_START, HTML_TAG_END, htmlContent) == 12
  check htmlContent == "</div>\n*foo*"

  # 120
  check parseHTMLBlockContent("<DIV class=\"foo\">\n\n*Markdown*\n\n</DIV>", HTML_TAG_START, HTML_TAG_END, htmlContent, ignoreCase=true) == 19
  check htmlContent == "<DIV class=\"foo\">\n\n"

  # 121
  check parseHTMLBlockContent("""<div id="foo"
  class="bar">
</div>""", HTML_TAG_START, HTML_TAG_END, htmlContent) == 35
  check htmlContent == """<div id="foo"
  class="bar">
</div>"""

  # 122
  check parseHTMLBlockContent("""<div id="foo" class="bar
  baz">
</div>""", HTML_TAG_START, HTML_TAG_END, htmlContent) == 39
  check htmlContent == """<div id="foo" class="bar
  baz">
</div>"""

  # 123
  check parseHTMLBlockContent("""<div>
*foo*

*bar*""", HTML_TAG_START, HTML_TAG_END, htmlContent) == 13
  check htmlContent == """<div>
*foo*

"""

  # 124
  check parseHTMLBlockContent("""<div id="foo"
*hi*""", HTML_TAG_START, HTML_TAG_END, htmlContent) == 18
  check htmlContent == """<div id="foo"
*hi*"""

  # 127
  check parseHTMLBlockContent("<div><a href=\"bar\">*foo*</a></div>", HTML_TAG_START, HTML_TAG_END, htmlContent) == 34
  check htmlContent == "<div><a href=\"bar\">*foo*</a></div>"

  # 129
  check parseHTMLBlockContent("<div></div>\n``` c\nint x = 33;\n```", HTML_TAG_START, HTML_TAG_END, htmlContent) == 33
  check htmlContent == "<div></div>\n``` c\nint x = 33;\n```"

  # 130
  check parseHTMLBlockContent("""<a href="foo">
*bar*
</a>""", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == 25
  check htmlContent == """<a href="foo">
*bar*
</a>"""

  # 131
  check parseHTMLBlockContent("""<Warning>
*bar*
</Warning>""", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == 26
  check htmlContent == """<Warning>
*bar*
</Warning>"""

  # 132
  check parseHTMLBlockContent("""<i class="foo">
*bar*
</i>""", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == 26
  check htmlContent == """<i class="foo">
*bar*
</i>"""

  # 133
  check parseHTMLBlockContent("""</ins>
*bar*""", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == 12
  check htmlContent == """</ins>
*bar*"""

  # 134
  check parseHTMLBlockContent("""<del>
*foo*
</del>""", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == 18
  check htmlContent == """<del>
*foo*
</del>"""

  # 135
  check parseHTMLBlockContent("""<del>

*foo*

</del>""", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == 7
  check htmlContent == "<del>\n\n"

  # 136
  check parseHTMLBlockContent("<del>*foo*</del>", HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent) == -1

  # 144
  check parseHTMLBlockContent("""<!-- foo -->*bar*
*baz*""", HTML_COMMENT_START, HTML_COMMENT_END, htmlContent) == 18
  check htmlContent == "<!-- foo -->*bar*\n"

  # 145
  check parseHTMLBlockContent("""<script>
foo
</script>1. *bar*""", HTML_SCRIPT_START, HTML_SCRIPT_END, htmlContent) == 30
  check htmlContent == """<script>
foo
</script>1. *bar*"""

  # 147
  check parseHTMLBlockContent("<?php\n\necho '>'\n\n?>", HTML_PROCESSING_INSTRUCTION_START, HTML_PROCESSING_INSTRUCTION_END, htmlContent) == 19
  check htmlContent == "<?php\n\necho '>'\n\n?>"

  # 148
  check parseHTMLBlockContent("<!DOCTYPE html>", HTML_DECLARATION_START, HTML_DECLARATION_END, htmlContent) == 15
  check htmlContent == "<!DOCTYPE html>"

  check parseHTMLBlockContent("""<![CDATA[
function matchwo(a,b)
]]>
okay""", HTML_CDATA_START, HTML_CDATA_END, htmlContent) == 36
  check htmlContent == """<![CDATA[
function matchwo(a,b)
]]>
"""

  # 150
  check parseHTMLBlockContent("    <!-- dah -->", HTML_COMMENT_START, HTML_COMMENT_END, htmlContent) == -1

test "parse table rows & aligns":
  check parseTableRow("|a|") == @["", "a", ""]
  check parseTableRow("|a|b|") == @["", "a", "b", ""]
  check parseTableRow("|`a|b`|") == @["", "`a|b`", ""]
  check parseTableRow(r"|\`a|\`b|") == @["", r"\`a", r"\`b", ""]
  check parseTableRow("a") == @["a"]
  check parseTableRow("a|b") == @["a", "b"]
  var tableAlignMatches: seq[string] = @[]
  check parseTableAligns("| --- | --- |", tableAlignMatches) == true
  check tableAlignMatches == @["", ""]
  tableAlignMatches = @[]
  check parseTableAligns(":-: | -----------:", tableAlignMatches) == true
  check tableAlignMatches == @["center", "right"]
  tableAlignMatches = @[]
  check parseTableAligns("| ------ |", tableAlignMatches) == true
  check tableAlignMatches == @[""]

test "parse setext heading content":
  var level = 0
  var content = ""
  check parseSetextHeadingContent("a", content, level) == -1
  check parseSetextHeadingContent("a\n-", content, level) == 3
  check content == "a\n"
  check level == 2
  check parseSetextHeadingContent("F\n==\n\nF\n--\n", content, level) == 5
  check content == "F\n"
  check level == 1
  check parseSetextHeadingContent("F\nb\n====\n", content, level) == 9
  check content == "F\nb\n"
  check level == 1
  check parseSetextHeadingContent("   F\n-\n", content, level) == 7
  check content == "   F\n"
  check level == 2
  # 54: parseSetextHeadingContent cannot tell 4 spaces.
  check parseSetextHeadingContent("Foo\n    --", content, level) == -1
  #check parseSetextHeading("")

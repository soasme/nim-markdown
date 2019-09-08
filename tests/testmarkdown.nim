# To run these tests, simply execute `nimble test`.
# If you have `watchdog`(pip install watchdog), you can run `make test` to watch testing while

import unittest

import re, strutils, os, json, strformat, sequtils
import markdown


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
  check markdown("~~hello~~", config=initGfmConfig()) == "<p><del>hello</del></p>\n"
  check markdown("~~hello~~") == "<p>~~hello~~</p>\n"

test "escape \\":
  check markdown("1 < 2") == "<p>1 &lt; 2</p>\n"

test "table":
  check markdown("""
| Header 1 | Header 2 | Header 3 | Header 4 |
| :------: | -------: | :------- | -------- |
| Cell 1   | Cell 2   | Cell 3   | Cell 4   |
| Cell 5   | Cell 6   | Cell 7   | Cell 8   |
  """,
    config=initGfmConfig(),
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
| Cell 3   | Cell 4""",
    config=initGfmConfig(),
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

test "parse table rows & aligns":
  check parseTableRow("|a|") == @["", "a", ""]
  check parseTableRow("|a|b|") == @["", "a", "b", ""]
  check parseTableRow("|`a|b`|") == @["", "`a|b`", ""]
  check parseTableRow(r"|\`a|\`b|") == @["", r"\`a", r"\`b", ""]
  check parseTableRow("a") == @["a"]
  check parseTableRow("a|b") == @["a", "b"]
  check parseTableAligns("| --- | --- |") == (@["", ""], true)
  check parseTableAligns(":-: | -----------:") == (@["center", "right"], true)
  check parseTableAligns("| ------ |") == (@[""], true)

proc commonmarkThreaded(s: string) =
  discard markdown(s)

test "multithread":
  var thread: Thread[string]
  createThread(thread, commonmarkThreaded, "# Hello World")
  joinThread(thread)

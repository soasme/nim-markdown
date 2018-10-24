# To run these tests, simply execute `nimble test`.
# If you have `watchdog`(pip install watchdog), you can run `make test` to watch testing while

import unittest

import re, strutils, os, json, strformat
import markdown

const
  configKeepHtml = initMarkdownConfig(keepHtml = true)
  configNoEscape = initMarkdownConfig(escape = false)

# test "escape <tag>":
#   check escapeTag("hello <script>") == "hello &lt;script&gt;"

# test "escape quote":
#   check escapeQuote("hello 'world\"") == "hello &quote;world&quote;"

# test "escape & character":
#   check escapeAmpersandChar("hello & world") == "hello &amp; world"

# test "escape & sequence":
#   check escapeAmpersandSeq("hello & world") == "hello &amp; world"
#   check escapeAmpersandSeq("hello &amp; world") == "hello &amp; world"

test "preprocessing":
  check preprocessing("a\n   \nb\n") == "a\n\nb\n"
  check preprocessing("a\n   \n   \nb\n") == "a\n\n\nb\n"
  check preprocessing("a\rb") == "a\nb"
  check preprocessing("a\r\nb") == "a\nb"

test "newline":
  check markdown("\n\n\n") == ""

test "indented block code":
  check markdown("    proc helloworld():\n") == "<pre><code>proc helloworld():</code></pre>"
  check markdown("    proc helloworld():\n        echo(\"hello world\")\n"
    ) == "<pre><code>proc helloworld():\n    echo(\"hello world\")</code></pre>"

test "fencing block code":
  check markdown("```nim\nproc helloworld():\n  echo(\"hello world\")\n```"
    ) == "<pre><code lang=\"nim\">proc helloworld():\n  echo(\"hello world\")</code></pre>"
  check markdown("```\nproc helloworld():\n  echo(\"hello world\")\n```"
    ) == "<pre><code lang=\"\">proc helloworld():\n  echo(\"hello world\")</code></pre>"

test "paragraph":
  check markdown("hello world") == "<p>hello world</p>"
  check markdown("p1\np2\n") == "<p>p1\np2</p>"
  check markdown("p1\n") == "<p>p1</p>"
  check markdown("p1\n\np2\n") == "<p>p1</p><p>p2</p>"

test "bulleted item list":
  check markdown("* a\n* b\n") == "<ul><li>a</li><li>b</li></ul>"
  check markdown("* a\n  * b\n") == "<ul><li>a<ul><li>b</li></ul></li></ul>"
  check markdown("* a\n  * b\n* c") == "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>"
  check markdown("+ a\n+ b\n") == "<ul><li>a</li><li>b</li></ul>"
  check markdown("- a\n- b\n") == "<ul><li>a</li><li>b</li></ul>"
  check markdown("1. a\n2. b\n") == "<ol><li>a</li><li>b</li></ol>"
  check markdown("1. a\n* b\n") == "<ol><li>a</li><li>b</li></ol>"

test "define link":
  check markdown("[1]: https://example.com") == ""

test "html block":
  check markdown("<hr>\n\n", configKeepHtml) == "<hr>"
  check markdown("<!-- comment -->\n\n", configKeepHtml) == "<!-- comment -->"
  check markdown("<strong>hello world</strong>\n\n", configKeepHtml) == "<p><strong>hello world</strong></p>"
  check markdown("<strong class='special'>hello world</strong>\n\n", configKeepHtml) == "<p><strong class='special'>hello world</strong></p>"
  check markdown("<strong class=\"special\">hello world</strong>\n\n", configKeepHtml) == "<p><strong class=\"special\">hello world</strong></p>"

test "html block: default not keeping":
  check markdown("<hr>\n\n") == "&lt;hr&gt;"
  check markdown("<!-- comment -->\n\n") == "&lt;!-- comment --&gt;"
  check markdown("<strong>hello world</strong>\n\n") == "<p>&lt;strong&gt;hello world&lt;/strong&gt;</p>"
  check markdown("<strong class='special'>hello world</strong>\n\n"
    ) == "<p>&lt;strong class='special'&gt;hello world&lt;/strong&gt;</p>"
  check markdown("<strong class=\"special\">hello world</strong>\n\n"
    ) == "<p>&lt;strong class=\"special\"&gt;hello world&lt;/strong&gt;</p>"

test "html block: force not keeping":
  let config = initMarkdownConfig(keepHtml = false)
  check markdown("<hr>\n\n", config) == "&lt;hr&gt;"
  check markdown("<!-- comment -->\n\n", config) == "&lt;!-- comment --&gt;"
  check markdown("<strong>hello world</strong>\n\n", config) == "<p>&lt;strong&gt;hello world&lt;/strong&gt;</p>"
  check markdown("<strong class='special'>hello world</strong>\n\n", config
    ) == "<p>&lt;strong class='special'&gt;hello world&lt;/strong&gt;</p>"
  check markdown("<strong class=\"special\">hello world</strong>\n\n", config
    ) == "<p>&lt;strong class=\"special\"&gt;hello world&lt;/strong&gt;</p>"

test "inline autolink":
  check markdown("email to <test@example.com>") == "<p>email to <a href=\"mailto:test@example.com\">test@example.com</a></p>"
  check markdown("go to <https://example.com>") == "<p>go to <a href=\"https://example.com\">https://example.com</a></p>"
  check markdown("go to <http://example.com>") == "<p>go to <a href=\"http://example.com\">http://example.com</a></p>"

test "inline escape":
  check markdown("""\<p\>""") == "<p>&lt;p&gt;</p>"

test "inline html":
  check markdown("hello <em>world</em>", configKeepHtml) == "<p>hello <em>world</em></p>"
  check markdown("hello <em>world</em>") == "<p>hello &lt;em&gt;world&lt;/em&gt;</p>"

test "inline link":
  check markdown("[test](https://example.com)") == """<p><a href="https://example.com" title="">test</a></p>"""
  check markdown("[test](<https://example.com>)") == """<p><a href="https://example.com" title="">test</a></p>"""
  check markdown("[test](<https://example.com> 'hello')") == """<p><a href="https://example.com" title="hello">test</a></p>"""
  check markdown("[test](<https://example.com> \"hello\")") == """<p><a href="https://example.com" title="hello">test</a></p>"""
  check markdown("![test](https://example.com)") == """<p><img src="https://example.com" alt="test"></p>"""

test "inline reflink":
  check markdown("[test][Example]\n\n[test]: https://example.com"
    ) == """<p><a href="https://example.com" title="">Example</a></p>"""
  check markdown("[test]  [Example]\n\n[test]: https://example.com"
    ) == """<p><a href="https://example.com" title="">Example</a></p>"""
  check markdown("[test][Example]\n\n[test]: https://example.com \"TEST\""
    ) == """<p><a href="https://example.com" title="TEST">Example</a></p>"""

test "inline nolink":
  check markdown("[test]\n\n[test]: https://example.com"
    ) == """<p><a href="https://example.com" title="">test</a></p>"""
  check markdown("[test]\n\n[test]: https://example.com \"TEST\""
    ) == """<p><a href="https://example.com" title="TEST">test</a></p>"""


test "inline url":
  check markdown("https://example.com"
    ) == """<p><a href="https://example.com">https://example.com</a></p>"""

test "inline double emphasis":
  check markdown("**a**") == """<p><strong>a</strong></p>"""
  check markdown("__a__") == """<p><strong>a</strong></p>"""

test "inline emphasis":
  check markdown("*a*") == """<p><em>a</em></p>"""
  check markdown("_a_") == """<p><em>a</em></p>"""

test "inline code":
  check markdown("`code`") == """<p><code>code</code></p>"""
  check markdown("``code``") == """<p><code>code</code></p>"""
  check markdown("```code```") == """<p><code>code</code></p>"""

test "inline break":
  check markdown("hello\nworld") == "<p>hello\nworld</p>"
  check markdown("hello\\\nworld") == "<p>hello<br />\nworld</p>"
  check markdown("hello  \nworld") == "<p>hello<br />\nworld</p>"

test "inline strikethrough":
  check markdown("~~hello~~") == "<p><del>hello</del></p>"

test "inline footnote":
  check markdown("[^x]\n\n[^x]: abc") == """<p><sup class="footnote-ref" id="footnote-ref-x">""" &
    """<a href="#footnote-x">x</a></sup></p>"""

test "escape \\":
  check markdown("1 < 2") == "<p>1 &lt; 2</p>"
  check markdown("1 < 2", configNoEscape) == "<p>1 < 2</p>"

test "table":
  check markdown("""
| Header 1 | Header 2 | Header 3 | Header 4 |
| :------: | -------: | :------- | -------- |
| Cell 1   | Cell 2   | Cell 3   | Cell 4   |
| Cell 5   | Cell 6   | Cell 7   | Cell 8   |
  """) == """<table>
  <thead>
    <tr>
      <th style="text-align: center">Header 1</th>
      <th style="text-align: right">Header 2</th>
      <th style="text-align: left">Header 3</th>
      <th>Header 4</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Cell 1</td><td>Cell 2</td><td>Cell 3</td><td>Cell 4</td></tr>
    <tr><td>Cell 5</td><td>Cell 6</td><td>Cell 7</td><td>Cell 8</td></tr>
  </tbody>
</table>""".replace(re"\n *", "")

  check markdown("""
| Header 1 | Header 2
| -------- | --------
| Cell 1   | Cell 2
| Cell 3   | Cell 4""") == """
<table>
  <thead>
    <tr>
      <th>Header 1</th>
      <th>Header 2</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Cell 1</td><td>Cell 2</td></tr>
    <tr><td>Cell 3</td><td>Cell 4</td></tr>
  </tbody>
</table>""".replace(re"\n *", "")

# https://github.github.com/gfm/

test "gfm 1, 2, 3":
  discard """Tabs in lines are not expanded to spaces.
  However, in contexts where whitespace helps to define block structure,
  tabs behave as if they were replaced by spaces with a tab stop of 4 characters."""
  check markdown("\tfoo\tbaz\t\tbim") == "<pre><code>foo\tbaz\t\tbim</code></pre>"
  check markdown("  \tfoo\tbaz\t\tbim") == "<pre><code>foo\tbaz\t\tbim</code></pre>"
  check markdown("    a\ta\n    ὐ\ta") == "<pre><code>a\ta\nὐ\ta</code></pre>"

test "gfm 4, 5, 6, 7, 8, 9, 10, 11":
  discard "tab case failed."
  skip

test "gfm 2.3 Insecure characters":
  check markdown("\u0000 insecure") == "<p>\ufffd insecure</p>"

test "gfm 12":
  discard """Indicators of block structure always take precedence over indicators of inline structure."""
  check markdown("- `one\n- two`") == "<ul><li>`one</li><li>two`</li></ul>"

test "gfm 13":
  discard """A line consisting of 0-3 spaces of indentation,
  followed by a sequence of three or more matching -, _, or * characters,
  each followed optionally by any number of spaces or tabs, forms a thematic break."""
  check markdown("---\n___\n***") == "<hr /><hr /><hr />"
  check markdown("   ---\n") == "<hr />"

test "gfm 14":
  check markdown("+++") == "<p>+++</p>"

test "gfm 15":
  check markdown("===") == "<p>===</p>"

test "gfm 16":
  check markdown("--\n**\n__") == "<p>--\n**\n__</p>"

test "gfm 17":
  check markdown(" ***\n  ***\n   ***") == "<hr /><hr /><hr />"

test "gfm 18":
  check markdown("    ***\n") == "<pre><code>***</code></pre>"

test "gfm 19":
  skip # check markdown("Foo\n    ***") == "<p>Foo\n    ***</p>"

test "gfm 20":
  check markdown("_____________________________________") == "<hr />"

test "gfm 21":
  check markdown(" - - -") == "<hr />"

test "gfm 22":
  check markdown(" **  * ** * ** * **") == "<hr />"

test "gfm 23":
  check markdown("-     -      -      -") == "<hr />"

test "gfm 24":
  check markdown("- - - -    ") == "<hr />"

test "gfm 25":
  skip # check markdown("_ _ _ _ a\n\na------\n\n---a---") == "<p>_ _ _ _ a</p><p>a------</p><p>---a---</p>"

test "gfm 26":
  check markdown(" *-*") == "<p><em>-</em></p>"

test "gfm 27":
  check markdown("- foo\n***\n- bar") == """<ul>
  <li>foo</li>
  </ul>
  <hr />
  <ul>
  <li>bar</li>
  </ul>""".replace(re"\n *", "")

test "gfm 28":
  check markdown("""Foo
***
bar""") == "<p>Foo</p><hr /><p>bar</p>"

test "gfm 29":
  check markdown("Foo\n---\nbar") == "<h2>Foo</h2><p>bar</p>"

test "gfm 30":
  check markdown("* Foo\n* * *\n* Bar") == """<ul>
  <li>Foo</li>
  </ul>
  <hr />
  <ul>
  <li>Bar</li>
  </ul>""".replace(re"\n *", "")

test "gfm 31":
  skip
  # check markdown("- Foo\n- * * *") == """<ul>
  # <li>Foo</li>
  # <li>
  # <hr />
  # </li>
  # </ul>""".replace(re"\n *", "")

test "gfm 32":
  check markdown("""# foo
## foo
### foo
#### foo
##### foo
###### foo"""
  ) == """<h1>foo</h1>
<h2>foo</h2>
<h3>foo</h3>
<h4>foo</h4>
<h5>foo</h5>
<h6>foo</h6>""".replace(re"\n *", "")

test "gfm 33":
  check markdown("####### foo") == "<p>####### foo</p>"

test "gfm 34":
  check markdown("#5 bolt\n\n#hashtag") == "<p>#5 bolt</p><p>#hashtag</p>"

test "gfm 35":
  check markdown("\\## foo") == "<p>## foo</p>"

test "gfm 36":
  check markdown("# foo *bar* \\*baz\\*") == "<h1>foo <em>bar</em> *baz*</h1>"

test "gfm 37":
  check markdown("#                  foo                     ") == "<h1>foo</h1>"

test "gfm 38":
  check markdown("""
 ### foo
  ## foo
   # foo""") == "<h3>foo</h3><h2>foo</h2><h1>foo</h1>"

test "gfm 39":
  check markdown("    # foo") == "<pre><code># foo</code></pre>"

test "gfm 40":
  check markdown("foo\n    # bar") == "<p>foo\n# bar</p>"

test "gfm 41":
  check markdown("## foo ##\n###   bar    ###") == "<h2>foo</h2><h3>bar</h3>"

test "gfm 42":
  check markdown("# foo ##################################\n##### foo ##") == "<h1>foo</h1><h5>foo</h5>"

test "gfm 43":
  check markdown("### foo ###     ") == "<h3>foo</h3>"

test "gfm 44":
  check markdown("### foo ### b") == "<h3>foo ### b</h3>"

test "gfm 45":
  check markdown("# foo#") == "<h1>foo#</h1>"

test "gfm 46":
  check markdown(r"### foo \###") == "<h3>foo ###</h3>"
  check markdown(r"## foo #\##") == "<h2>foo ###</h2>"
  check markdown(r"# foo \#") == "<h1>foo #</h1>"

test "gfm 47":
  check markdown("****\n## foo\n****") == "<hr /><h2>foo</h2><hr />"

test "gfm 48":
  skip # check markdown("Foo bar\n# baz\nBar foo") == "<p>Foo bar</p><h1>baz</h1><p>Bar foo</p>"

test "gfm 49":
  check markdown("## \n#\n### ###") == "<h2></h2><h1></h1><h3></h3>"

test "gfm 50":
  check markdown("""
Foo *bar*
=========

Foo *bar*
---------""") == """
<h1>Foo <em>bar</em></h1>
<h2>Foo <em>bar</em></h2>""".replace(re"\n *", "")

test "gfm 51":
  skip
#   check markdown("""
# Foo *bar
# baz*
# ====""") == "<h1>Foo <em>bar\nbaz</em></h1>"

test "gfm 52":
  check markdown("""Foo
---------------------

Foo
=""") == "<h2>Foo</h2><h1>Foo</h1>"

test "gfm 53":
  check markdown("""
   Foo
---

  Foo
-----

  Foo
  ===""") == "<h2>Foo</h2><h2>Foo</h2><h1>Foo</h1>"

test "gfm 54":
  check markdown("    Foo\n    ---\n\n    Foo\n---"
    ) == "<pre><code>Foo\n---\n\nFoo</code></pre><hr />"

test "gfm 55":
  check markdown("Foo\n   ----      ") == "<h2>Foo</h2>"

test "gfm 56":
  check markdown("Foo\n    ----") == "<p>Foo\n----</p>"

test "gfm 57":
  check markdown("Foo\n= =\n\nFoo\n--- -") == "<p>Foo\n= =</p><p>Foo</p><hr />"

test "gfm 58":
  check markdown("Foo  \n-----") == "<h2>Foo</h2>"

test "gfm 59":
  check markdown("Foo\\\n----") == r"<h2>Foo\</h2>"

test "gfm 60":
  check markdown("""
`Foo
----
`

<a title="a lot
---
of dashes"/>
""") == "<h2>`Foo</h2><p>`</p><h2>&lt;a title=&quot;a lot</h2><p>of dashes&quot;/&gt;</p>"

test "gfm 61":
  skip # check markdown("> Foo\n---") == "<blockquote><p>Foo</p></blockquote><hr />"

test "gfm 62":
  skip # check markdown("> foo\nbar\n===") == "<blockquote><p>foo\nbar\n===</p></blockquote>"

test "gfm 63":
  skip # check markdown("- Foo\n---") == "<ul><li>Foo</li></ul><hr />"

test "gfm 199":
  check markdown("""> # Foo
> bar
> baz""") == """<blockquote><h1>Foo</h1><p>bar
baz</p></blockquote>"""

test "gfm 200":
  check markdown("""># Foo
>bar
> baz""") == """<blockquote><h1>Foo</h1><p>bar
baz</p></blockquote>"""

test "gfm 201":
  check markdown("""   > # Foo
   > bar
 > baz""") == """<blockquote><h1>Foo</h1><p>bar
baz</p></blockquote>"""

test "gfm 202":
  check markdown("""    > # Foo
    > bar
    > baz""") == """<pre><code>&gt; # Foo
&gt; bar
&gt; baz</code></pre>"""

test "gfm 203":
  check markdown("""> # Foo
> bar
baz""") == """<blockquote><h1>Foo</h1><p>bar
baz</p></blockquote>"""

test "gfm 204":
  check markdown("""> bar
baz
> foo""") == """<blockquote><p>bar
baz
foo</p></blockquote>"""

test "gfm 205":
  skip #check markdown("""> foo
#---""") == """<blockquote><p>foo</p></blockquote><hr />"""

test "gfm 206":
  skip
  #check markdown("""> - foo
#- bar""") == """<blockquote>
#<ul>
#<li>foo</li>
#</ul>
#</blockquote>
#<ul>
#<li>bar</li>
#</ul>"""

test "gfm 207":
  skip
  #check markdown(""">     foo
    #bar""") == """<blockquote>
#<pre><code>foo
#</code></pre>
#</blockquote>
#<pre><code>bar
#</code></pre>"""

test "gfm 208":
  skip
  #check markdown("""> ```
#foo
#```""") == """<blockquote>
#<pre><code></code></pre>
#</blockquote>
#<p>foo</p>
#<pre><code></code></pre>"""

test "gfm 209":
  check markdown("""> foo
    - bar""") == """<blockquote><p>foo
- bar</p></blockquote>"""

test "gfm 210":
  check markdown(">") == "<blockquote></blockquote>"

test "gfm 211":
  check markdown(">\n>  \n> ") == "<blockquote></blockquote>"

test "gfm 212":
  check markdown(">\n> foo\n>  ") == "<blockquote><p>foo</p></blockquote>"

test "gfm 213":
  skip # check markdown("> foo\n\n> bar") == "<blockquote><p>foo</p></blockquote><blockquote><p>bar</p></blockquote>"

test "gfm 214":
  check markdown("> foo\n> bar") == """<blockquote><p>foo
bar</p></blockquote>"""

test "gfm 215":
  check markdown("> foo\n>\n> bar") == "<blockquote><p>foo</p><p>bar</p></blockquote>"

test "gfm 216":
  check markdown("""foo
> bar""") == """<p>foo</p><blockquote><p>bar</p></blockquote>"""

test "gfm 217":
  skip
  #check markdown("""> aaa
#***
#> bbb""") == """<blockquote><p>aaa</p></blockquote><hr /><blockquote><p>bbb</p></blockquote>"""

test "gfm 218":
  check markdown("""> bar
baz""") == """<blockquote><p>bar
baz</p></blockquote>"""

test "gfm 219":
  check markdown("""> bar

baz""") == "<blockquote><p>bar</p></blockquote><p>baz</p>"

test "gfm 220":
  skip
  #check markdown("""> bar
#>
#baz""") == """<blockquote><p>bar</p></blockquote><p>baz</p>"""

test "gfm 221":
  check markdown("""> > > foo
bar""") == """<blockquote><blockquote><blockquote><p>foo
bar</p></blockquote></blockquote></blockquote>"""

test "gfm 222":
  check markdown(""">>> foo
> bar
>>baz""") == """<blockquote><blockquote><blockquote><p>foo
bar
baz</p></blockquote></blockquote></blockquote>"""

test "gfm 223":
  skip
  #check markdown(""">     code

#>    not code""") == """<blockquote><pre><code>code
#</code></pre></blockquote><blockquote><p>not code</p></blockquote>"""

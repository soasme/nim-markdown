# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import markdownpkg/submodule

test "escape <tag>":
  check escapeTag("hello <script>") == "hello &lt;script&gt;"

test "escape quote":
  check escapeQuote("hello 'world\"") == "hello &quote;world&quote;"

test "escape & character":
  check escapeAmpersandChar("hello & world") == "hello &amp; world"

test "escape & sequence":
  check escapeAmpersandSeq("hello & world") == "hello &amp; world"
  check escapeAmpersandSeq("hello &amp; world") == "hello &amp; world"

test "headers":
  check markdown("#h1") == "<h1>h1</h1>"
  check markdown("# h1") == "<h1>h1</h1>"
  check markdown(" #h1") == "<h1>h1</h1>"
  check markdown("## h2") == "<h2>h2</h2>"
  check markdown("### h3") == "<h3>h3</h3>"
  check markdown("#### h4") == "<h4>h4</h4>"
  check markdown("##### h5") == "<h5>h5</h5>"
  check markdown("###### h6") == "<h6>h6</h6>"

test "text":
  check markdown("hello world") == "hello world"

  test "preprocessing":
    check preprocessing("a\n   \nb\n") == "a\n\nb\n"
    check preprocessing("a\tb") == "a    b"
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
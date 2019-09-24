# Advance Usages

Note that Nim-markdown APIs are subject to change before v1.0.0.
Examples on this document might not fully work til then.

## Customize Parsing

Sometimes, you want to add new parsing rules.  In this example, we'll implement a new block parser called `IncludeParser` that can dynamically include markdown document in another file. The rule applies to customized inline parsers.

For example,

```
#include "another-file.md"
```

In `another-file.md`, it has content:

```
# Not include, but a header.
```

First, let's define a parser. It inherits from `Parser`.

```nim
import markdown

type IncludeParser = ref object of Parser
```

Next, we'll define a token that is inherited from `Block`.

```nim
type IncludeToken = ref object of Block
    path: string
```

The trickiest part is to register the new parser. We achieve this by inserting it into `MarkdownConfig.blockParsers` or `MarkdownConfig.inlineParsers`, depending on what kind of parser you want to add. For example, we expect `IncludeParser()` to be a block parser, and perform the parsing before any other parsers.

```nim
var c = initCommonmarkConfig()
c.blockParsers.insert(IncludeParser(), 0)
```

Then, we define how to parse doc for `IncludeParser` and how to render the token for `IncludeToken`.

```nim
import strutils, sequtils, strscans, system, os

method parse(parser: IncludeParser, doc: string, start: int): ParseResult  {.locks: "unknown".}=
  var idx = start
  var path = ""

  if scanp(
    doc, idx,
    (
      "#include", # it starts with `#include`
      +{' ', '\t'}, # it requires at least one whitespace.
      '"',  # it requires double quote
      +( ~{'"', '\n'} -> path.add($_)), # it requires a path to the filename.
      '"',
      *{' ', '\n'}, # it allows trailing whitespaces.
    )
  ):
    ParseResult(token: IncludeToken(path: path), pos: idx)
  else:
    ParseResult(token: nil, pos: -1) # -1 means not advancing the doc.

method `$`(token: IncludeToken): string =
  markdown(token.path.readFile, c)
```

At last, call `markdown()` with the modified config object.

```nim
let md = """
#include nothing

#include "hello.md"
"""

echo(markdown(md, c))
```

It should output the html as below:

```html
<p>#include nothing</p>
<h1>I'm included.</h1>

```

## Operate AST

Proc `markdown` supports an additional `root=` argument.
By default, it's `Document()`. You can set a new root for further operating.
For example,

```nim
let root = Document()
discard markdown("# Hello World\nTest.", root=root)
```

After calling `markdown()`, `root` is a fully parsed abstracted syntax tree.
You can add some new nodes to it.
For example,

```nim
let p = Paragraph(loose: true)
let em = Em()
let text = Text(doc: "emphasis text.")
em.appendChild(text)
p.appendChild(em)
root.appendChild(p)
```

You can render the modified root by calling `render()`:

```nim
render(root)
```

It'll render a new paragraph as expected:

```html
<h1>Hello World</h1>
<p>Test.</p>
<p><em>emphasis text.</em></p>
```

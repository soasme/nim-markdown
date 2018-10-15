# nim-markdown
#
# A Markdown parser in Nim programming language.
#
# Users of bin command can handle markdown document in a bash command like below.
#
# ```bash
# $ markdown < file.md > file.html`
# ```
#
# Users of library will import this file by writing ``import markdownpkg/core``.
#
# :copyright: (c) 2018 by Ju Lin.
# :license: MIT.

import re, strutils, strformat, tables, sequtils, math

type
  MarkdownError* = object of Exception

  # Type for saving parsing context.
  MarkdownContext* = object
    # `links` is for saving links like `[xyz]: https://...`.
    # We need to save these links for forward/backward references.
    links: Table[string, string]
    listDepth: int

  # Type for header element
  Header* = object
    doc: string
    level: int

  # Type for fencing block code
  Fence* = object
    code: string
    lang: string

  # Type for list item
  ListItem* = object
    doc: MarkdownTokenRef

  # Type for list block
  ListBlock* = object
    elems: iterator(): ListItem
    depth: int
    ordered: bool

  # Type for defining link
  DefineLink* = object
    text: string
    link: string

  # Signify the token type
  MarkdownTokenType* {.pure.} = enum
    Header,
    Hrule,
    IndentedBlockCode,
    FencingBlockCode,
    Paragraph,
    Text,
    ListItem,
    ListBlock,
    BlockQuote,
    DefineLink,
    Newline

  # Hold two values: type: MarkdownTokenType, and xyzValue.
  # xyz is the particular type name.
  MarkdownTokenRef* = ref MarkdownToken
  MarkdownToken* = object
    pos: int
    len: int
    case type*: MarkdownTokenType
    of MarkdownTokenType.Header: headerVal*: Header
    of MarkdownTokenType.Hrule: hruleVal*: string
    of MarkdownTokenType.BlockQuote: blockQuoteVal*: string
    of MarkdownTokenType.IndentedBlockCode: codeVal*: string
    of MarkdownTokenType.FencingBlockCode: fencingBlockCodeVal*: Fence
    of MarkdownTokenType.Paragraph: paragraphVal*: string
    of MarkdownTokenType.Text: textVal*: string
    of MarkdownTokenType.Newline: newlineVal*: string
    of MarkdownTokenType.ListBlock: listBlockVal*: ListBlock
    of MarkdownTokenType.ListItem: listItemVal*: ListItem
    of MarkdownTokenType.DefineLink: defineLinkVal*: DefineLink

var blockRules = @{
  MarkdownTokenType.Header: re"^ *(#{1,6}) *([^\n]+?) *#* *(?:\n+|$)",
  MarkdownTokenType.Hrule: re"^ {0,3}[-*_](?: *[-*_]){2,} *(?:\n+|$)",
  MarkdownTokenType.IndentedBlockCode: re"^(( {4}[^\n]+\n*)+)",
  MarkdownTokenType.FencingBlockCode: re"^( *`{3,} *([^`\s]+)? *\n([\s\S]+?)\s*`{3} *(\n+|$))",
  MarkdownTokenType.BlockQuote: re"^(( *>[^\n]+(\n[^\n]+)*\n*)+)",
  MarkdownTokenType.Paragraph: re(
    r"^(((?:[^\n]+\n?" &
    r"(?!" &
    r" *(#{1,6}) *([^\n]+?) *#* *(?:\n+|$)|" & # header
    r" {0,3}[-*_](?: *[-*_]){2,} *(?:\n+|$)|" & # hrule
    r"(( *>[^\n]+(\n[^\n]+)*\n*)+)" & # blockQuote
    r"))+)\n*)"
  ),
  MarkdownTokenType.ListBlock: re(
    r"^(" & # group 0 is itself.
    r"( *)(?=[*+-]|\d+\.)" & # set group 1 to indent. 
    r"(([*+-])?(?:\d+\.)?) " & # The leading of the indent is list mark `* `, `- `, `+ `, and `1. `.
    r"[\s\S]+?" & # first list item content (optional).
    r"(?:" & # support below block prepending the list block (non-capturing).
    r"\n+(?=\1?(?:[-*_] *){3,}(?:\n+|$))" & # hrule
    r"|\n+(?=\1(?(3)\d+\.|[*+-]) )" & # mix using 1. and */+/-.
    r"|\n{2,}(?! )(?!\1(?:[*+-]|\d+\.) )\n*" &
    r"|\s*$" &
    r"))"
  ),
  MarkdownTokenType.ListItem: re(
    r"^(( *)(?:[*+-]|\d+\.) [^\n]*" &
    r"(?:\n(?!\2(?:[*+-]|\d+\.) )[^\n]*)*)",
    {RegexFlag.reMultiLine}
  ),
  MarkdownTokenType.DefineLink: re"^( *\[([^^\]]+)\]: *<?([^\s>]+)>?(?: +[\""(]([^\n]+)[\"")])? *(?:\n+|$))",
  MarkdownTokenType.Text: re"^([^\n]+)",
  MarkdownTokenType.Newline: re"^(\n+)",
}.newTable

let blockParsingOrder = @[
  MarkdownTokenType.Header,
  MarkdownTokenType.Hrule,
  MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  MarkdownTokenType.BlockQuote,
  MarkdownTokenType.ListBlock,
  MarkdownTokenType.DefineLink,
  MarkdownTokenType.Paragraph,
  MarkdownTokenType.Newline,
]

let listParsingOrder = @[
  MarkdownTokenType.Newline,
  MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  MarkdownTokenType.Header,
  MarkdownTokenType.Hrule,
  MarkdownTokenType.BlockQuote,
  MarkdownTokenType.Text,
]

proc preprocessing*(doc: string): string =
  # Pre-processing the text
  result = doc.replace(re"\r\n|\r", "\n")
  result = result.replace(re"\t", "    ")
  result = result.replace("\u2424", " ")
  result = result.replace(re(r"^ +$", {RegexFlag.reMultiLine}), "")

proc escapeTag*(doc: string): string =
  # Replace `<` and `>` to HTML-safe characters.
  # Example:
  #   >>> escapeTag("<tag>")
  #   "&lt;tag&gt;"
  result = doc.replace("<", "&lt;")
  result = result.replace(">", "&gt;")

proc escapeQuote*(doc: string): string =
  # Replace `'` and `"` to HTML-safe characters.
  # Example:
  #   >>> escapeTag("'tag'")
  #   "&quote;tag&quote;"
  result = doc.replace("'", "&quote;")
  result = result.replace("\"", "&quote;")

proc escapeAmpersandChar*(doc: string): string =
  # Replace character `&` to HTML-safe characters.
  # Example:
  #   >>> escapeAmpersandChar("&amp;")
  #   &amp;amp;
  result = doc.replace("&", "&amp;")

let reAmpersandSeq = re"&(?!#?\w+;)"

proc escapeAmpersandSeq*(doc: string): string =
  # Replace `&` from a sequence of characters starting from it to HTML-safe characters.
  # It's useful to keep those have been escaped.
  # Example:
  #   >>> escapeAmpersandSeq("&") # In this case, it's like `escapeAmpersandChar`.
  #   "&"
  #   >>> escapeAmpersandSeq("&amp;") # In this case, we preserve that has escaped.
  #   "&amp;"
  result = doc.replace(sub=reAmpersandSeq, by="&amp;")

proc escapeCode*(doc: string): string =
  # Make code block in markdown document HTML-safe.
  result = doc.strip(leading=false, trailing=true).escapeTag.escapeAmpersandChar

proc findToken(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef;

iterator parseTokens(doc: string): MarkdownTokenRef =
  # Parse markdown document into a sequence of tokens.
  var n = 0
  while n < doc.len:
    var token: MarkdownTokenRef = nil
    for ruleType in blockParsingOrder:
      token = findToken(doc, n, ruleType)
      if token != nil:
        yield token
        break
    if token == nil:
      raise newException(MarkdownError, fmt"unknown block rule at position {n}.")

# TODO: parse inline items.
# TODO: parse list item tokens.

iterator parseListTokens(doc: string): MarkdownTokenRef =
  let items = doc.findAll(blockRules[MarkdownTokenType.ListItem])
  for index, item in items:
    var val: ListItem
    var text = item.replace(re"^ *(?:[*+-]|\d+\.) +", "")
    val.doc = MarkdownTokenRef(pos: -1, len: item.len, type: MarkdownTokenType.Text, textVal: text)
    yield MarkdownTokenRef(pos: -1, len: 1, type: MarkdownTokenType.ListItem, listItemVal: val)

proc genNewlineToken(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  if matches[0].len > 1:
    result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.Newline, newlineVal: matches[0])

proc genHeaderToken(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var val: Header
  val.level = matches[0].len
  val.doc = matches[1]
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.Header, headerVal: val) 

proc genHruleToken(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.Hrule, hruleVal: "")

proc genBlockQuoteToken(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var quote = matches[0].replace(re(r"^ *> ?", {RegexFlag.reMultiLine}), "").strip(chars={'\n', ' '})
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.BlockQuote, blockQuoteVal: quote)

proc genIndentedBlockCode(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var code = matches[0].replace(re(r"^ {4}", {RegexFlag.reMultiLine}), "")
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.IndentedBlockCode, codeVal: code)

proc genFencingBlockCode(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var val: Fence
  val.lang = matches[1]
  val.code = matches[2]
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.FencingBlockCode, fencingBlockCodeVal: val)

proc genParagraph(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var val = matches[0].strip(chars={'\n', ' '})
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.Paragraph, paragraphVal: val)

proc genText(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.Text, textVal: matches[0])

proc genDefineLink(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var val: DefineLink
  val.text = matches[1]
  val.link = matches[2]
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.DefineLink, defineLinkVal: val)

proc genListBlock(matches: openArray[string], pos: int, size: int): MarkdownTokenRef =
  var val: ListBlock
  let doc = matches[0]
  val.ordered = matches[2] =~ re"\d+."
  val.elems = iterator(): ListItem =
    for token in parseListTokens(doc):
      yield ListItem(doc: token)
  result = MarkdownTokenRef(pos: pos, len: size, type: MarkdownTokenType.ListBlock, listBlockVal: val)

proc findToken(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef =
  # Find a markdown token from document `doc` at position `start`,
  # based on a rule type and regex rule.
  let regex = blockRules[ruleType]
  var matches: array[5, string]

  let size = doc[start .. doc.len - 1].matchLen(regex, matches=matches)
  if size == -1:
    return nil

  case ruleType
  of MarkdownTokenType.Newline: result = genNewlineToken(matches, start, size)
  of MarkdownTokenType.Header: result = genHeaderToken(matches, start, size)
  of MarkdownTokenType.Hrule: result = genHruleToken(matches, start, size)
  of MarkdownTokenType.BlockQuote: result = genBlockQuoteToken(matches, start, size)
  of MarkdownTokenType.IndentedBlockCode: result = genIndentedBlockCode(matches, start, size)
  of MarkdownTokenType.FencingBlockCode: result = genFencingBlockCode(matches, start, size)
  of MarkdownTokenType.DefineLink: result = genDefineLink(matches, start, size)
  of MarkdownTokenType.ListItem:
    var val: ListItem
    # TODO: recursively parse val.doc
    val.doc = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.Text, textVal: matches[0])
    result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.ListItem, listItemVal: val)
  of MarkdownTokenType.ListBlock: result = genListBlock(matches, start, size)
  of MarkdownTokenType.Paragraph: result = genParagraph(matches, start, size)
  of MarkdownTokenType.Text: result = genText(matches, start, size)

  start += size

proc renderHeader*(header: Header): string =
  # Render header tag, for example, `<h1>`, `<h2>`, etc.
  # Example:
  #   >>> renderHeader("hello world", level=1)
  #   "<h1>hello world</h1>"
  result = fmt"<h{header.level}>{header.doc}</h{header.level}>"

proc renderText*(text: string): string =
  # Render text by escaping itself.
  result = text.escapeAmpersandSeq.escapeTag

proc renderNewline*(newline: string): string =
  # Render newline, which adds an empty string to the result.
  result = ""

proc renderFencingBlockCode*(fence: Fence): string =
  # Render fencing block code
  result = fmt("<pre><code lang=\"{fence.lang}\">{escapeCode(fence.code)}</code></pre>")

proc renderIndentedBlockCode*(code: string): string =
  # Render indented block code.
  # The code content will be escaped as it might contains HTML tags.
  # By default the indented block code doesn't support code highlight.
  result = fmt"<pre><code>{escapeCode(code)}</code></pre>"

proc renderParagraph*(paragraph: string): string =
  result = fmt"<p>{paragraph}</p>"

proc renderHrule(hrule: string): string =
  result = "<hr>"

proc renderBlockQuote(blockQuote: string): string =
  result = fmt"<blockquote>{blockQuote}</blockquote>"

proc renderToken(ctx: MarkdownContext, token: MarkdownTokenRef): string;

proc renderListBlock(ctx: MarkdownContext, listBlock: ListBlock): string =
  result = ""
  for el in listBlock.elems():
    result &= renderToken(ctx, el.doc)
  if listBlock.ordered:
    result = fmt"<ol>{result}</ol>"
  else:
    result = fmt"<ul>{result}</ul>"

proc renderListItem(ctx: MarkdownContext, listItem: ListItem): string =
  let formattedDoc = renderToken(ctx, listItem.doc).strip(chars={'\n', ' '})
  result = fmt"<li>{formattedDoc}</li>"

proc renderDefineLink(ctx: MarkdownContext, defineLink: DefineLink): string =
  echo(ctx.links)
  result = ""

proc renderToken(ctx: MarkdownContext, token: MarkdownTokenRef): string =
  # Render token.
  # This is a simple dispatcher function.
  case token.type
  of MarkdownTokenType.Header:
    result = renderHeader(token.headerVal)
  of MarkdownTokenType.Hrule:
    result = renderHrule(token.hruleVal)
  of MarkdownTokenType.Text:
    result = renderText(token.textVal)
  of MarkdownTokenType.Newline:
    result = renderNewline(token.newlineVal)
  of MarkdownTokenType.IndentedBlockCode:
    result = renderIndentedBlockCode(token.codeVal)
  of MarkdownTokenType.FencingBlockCode:
    result = renderFencingBlockCode(token.fencingBlockCodeVal)
  of MarkdownTokenType.Paragraph:
    result = renderParagraph(token.paragraphVal)
  of MarkdownTokenType.BlockQuote:
    result = renderBlockQuote(token.blockQuoteVal)
  of MarkdownTokenType.ListBlock:
    result = renderListBlock(ctx, token.listBlockVal)
  of MarkdownTokenType.ListItem:
    result = renderListItem(ctx, token.listItemVal)
  of MarkdownTokenType.DefineLink:
    result = renderDefineLink(ctx, token.defineLinkVal)

proc buildContext(tokens: seq[MarkdownTokenRef]): MarkdownContext =
  result = MarkdownContext(links: initTable[string, string]())
  for token in tokens:
    case token.type
    of MarkdownTokenType.DefineLink:
      result.links[token.defineLinkVal.text] = token.defineLinkVal.link
    else:
      discard

# Turn markdown-formatted string into HTML-formatting string.
# By setting `escapse` to false, no HTML tag will be escaped.
proc markdown*(doc: string, escape: bool = true): string =
  let tokens = toSeq(parseTokens(preprocessing(doc)))
  let ctx = buildContext(tokens)
  for token in tokens:
      result &= renderToken(ctx, token)
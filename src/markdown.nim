# nim-markdown
#
## A beautiful Markdown parser in the Nim world.
##
## Usage of the binary: convert markdown document in bash like below.::
##
##    $ markdown < file.md > file.html
##
## Disable escaping characters via `--no-escape`::
##
##    $ markdown --no-escape < file.md
##
## Keep raw HTML content via `--keep-html`::
##
##    $ markdown --keep-html < file.md
##
## Usage of the library: import this file by writing `import markdown`.::
##
##     let s = markdown("# hello world")
##     echo(s)
##
## Options can be created with `initMarkdownConfig <#initMarkdownConfig%2C>`_.
## Choices of options are listed below:
##
## * `keepHtml`, default `false`.
## * `escape`, default `true`.
##
## With the default option, `Nim & Markdown` will be translated into `Nim &amp; Markdown`.
## If you want to escape no characters in the document, turn off `Escape`::
##
##     let config = initMarkdownConfig(escape = false)
##
##     let doc = """
##     # Hello World
##
##     Nim & Markdown
##     """
##
##     let html = markdown(doc, config)
##     echo(html) # <h1>Hello World</h1><p>Nim & Markdown</p>
##
## With the default option, `<em>Markdown</em>` will be translated into `&lt;em&gt;Markdown&lt;/em&gt;`.
## It's always recommended not keeping html when converting unless you know what you're doing.
##
## If you want to keep the raw html in the document, turn on `KeepHTML`::
##
##     let config = initMarkdownConfig(keepHtml = true)
##
##     let doc = """
##     # Hello World
##
##     Happy writing <em>Markdown</em> document!
##     """
##
##     let html = markdown(doc, config)
##     echo(html)
##     # <h1>Hello World</h1><p>Happy writing <em>Markdown</em> document!</p>
##
## :copyright: (c) 2018 by Ju Lin.
## :repo: https://github.com/soasme/nim-markdown
## :patreon: https://www.patreon.com/join/enqueuezero
## :license: MIT.

import re, strutils, strformat, tables, sequtils, math

const MARKDOWN_VERSION* = "0.3.4"

type
  MarkdownError* = object of Exception ## The error object for markdown parsing and rendering.

  Heading* = object ## The type for heading element.
    inlines: seq[MarkdownTokenRef]
    level: int

  Fence* = object ## The type for fences.
    code: string
    lang: string

  ListItem* = object ## The type for the list item
    blocks: seq[MarkdownTokenRef]

  ListBlock* = object ## The type for the list block
    blocks: seq[MarkdownTokenRef]
    depth: int
    ordered: bool

  DefineLink* = object ## The type for defining a link
    text: string
    title: string
    link: string

  DefineFootnote* = object ## The type for defining a footnote
    anchor: string
    footnote: string

  HTMLBlock* = object ## The type for a raw HTML block.
    tag: string
    attributes: string
    text: string

  Paragraph* = object ## The type for a paragraph
    inlines: seq[MarkdownTokenRef]

  Link* = object ## The type for a link in full format.
    url: string
    text: string
    title: string
    isImage: bool
    isEmail: bool

  RefLink* = object ## The type for a link in referencing mode.
    id: string
    text: string
    title: string
    isImage: bool

  RefFootnote* = object ## The type for a footnote in referencing mode.
    anchor: string

  TableCell* = object
    dom: seq[MarkdownTokenRef]
    align: string

  TableHead* = object
    cells: seq[TableCell]

  TableRow* = object
    cells: seq[TableCell]

  HTMLTable* = object
    head: TableHead
    body: seq[TableRow]

  BlockQuote* = object
    blocks: seq[MarkdownTokenRef]

  MarkdownConfig* = object ## Options for configuring parsing or rendering behavior.
    escape: bool ## escape ``<``, ``>``, and ``&`` characters to be HTML-safe
    keepHtml: bool ## preserve HTML tags rather than escape it

  MarkdownContext* = object ## The type for saving parsing context.
    links: Table[string, Link]
    footnotes: Table[string, string]
    listDepth: int
    config: MarkdownConfig

  MarkdownTokenType* {.pure.} = enum # All token types
    Heading,
    SetextHeading,
    ThematicBreak,
    IndentedBlockCode,
    FencingBlockCode,
    Paragraph,
    Text,
    ListItem,
    ListBlock,
    BlockQuote,
    DefineLink,
    DefineFootnote,
    HTMLBlock,
    HTMLTable,
    Newline,
    AutoLink,
    InlineEscape,
    InlineText,
    InlineHTML,
    InlineLink,
    InlineRefLink,
    InlineNoLink,
    InlineURL,
    InlineDoubleEmphasis,
    InlineEmphasis,
    InlineCode,
    InlineBreak,
    InlineStrikethrough,
    InlineFootnote

  MarkdownTokenRef* = ref MarkdownToken ## Hold two values:
                                        ## * type: MarkdownTokenType
                                        ## * xyzValue: xyz is the particular type name.
  MarkdownToken* = object
    len: int
    case type*: MarkdownTokenType
    of MarkdownTokenType.Heading: headingVal*: Heading
    of MarkdownTokenType.SetextHeading: setextHeadingVal*: Heading
    of MarkdownTokenType.ThematicBreak: thematicBreakVal*: string
    of MarkdownTokenType.BlockQuote: blockQuoteVal*: BlockQuote
    of MarkdownTokenType.IndentedBlockCode: codeVal*: string
    of MarkdownTokenType.FencingBlockCode: fencingBlockCodeVal*: Fence
    of MarkdownTokenType.Paragraph: paragraphVal*: Paragraph
    of MarkdownTokenType.Text: textVal*: string
    of MarkdownTokenType.Newline: newlineVal*: string
    of MarkdownTokenType.AutoLink: autoLinkVal*: Link
    of MarkdownTokenType.InlineText: inlineTextVal*: string
    of MarkdownTokenType.InlineEscape: inlineEscapeVal*: string
    of MarkdownTokenType.ListBlock: listBlockVal*: ListBlock
    of MarkdownTokenType.ListItem: listItemVal*: ListItem
    of MarkdownTokenType.DefineLink: defineLinkVal*: DefineLink
    of MarkdownTokenType.DefineFootnote: defineFootnoteVal*: DefineFootnote
    of MarkdownTokenType.HTMLBlock: htmlBlockVal*: HTMLBlock
    of MarkdownTokenType.HTMLTable: htmlTableVal*: HTMLTable
    of MarkdownTokenType.InlineHTML: inlineHTMLVal*: HTMLBlock
    of MarkdownTokenType.InlineLink: inlineLinkVal*: Link
    of MarkdownTokenType.InlineRefLink: inlineRefLinkVal*: RefLink
    of MarkdownTokenType.InlineNoLink: inlineNoLinkVal*: RefLink
    of MarkdownTokenType.InlineURL: inlineURLVal*: string
    of MarkdownTokenType.InlineDoubleEmphasis: inlineDoubleEmphasisVal*: string
    of MarkdownTokenType.InlineEmphasis: inlineEmphasisVal*: string
    of MarkdownTokenType.InlineCode: inlineCodeVal*: string
    of MarkdownTokenType.InlineBreak: inlineBreakVal*: string
    of MarkdownTokenType.InlineStrikethrough: inlineStrikethroughVal*: string
    of MarkdownTokenType.InlineFootnote: inlineFootnoteVal*: RefFootnote

const INLINE_TAGS* = [
    "a", "em", "strong", "small", "s", "cite", "q", "dfn", "abbr", "data",
    "time", "code", "var", "samp", "kbd", "sub", "sup", "i", "b", "u", "mark",
    "ruby", "rt", "rp", "bdi", "bdo", "span", "br", "wbr", "ins", "del",
    "img", "font",
]

proc initMarkdownConfig*(
  escape = true,
  keepHtml = true
): MarkdownConfig =
  MarkdownConfig(
    escape: escape,
    keepHtml: keepHtml
  )

let blockTagAttribute = """\s*[a-zA-Z\-](?:\s*\=\s*(?:"[^"]*"|'[^']*'|[^\s'">]+))?"""
let blockTag = r"(?!(?:" & fmt"{INLINE_TAGS.join(""|"")}" & r")\b)\w+(?!:/|[^\w\s@]*@)\b"

var blockRules = @{
  MarkdownTokenType.Heading: re"^ *(#{1,6})( +)?(?(2)([^\n]*?))( +)?(?(4)#*) *(?:\n+|$)",
  MarkdownTokenType.SetextHeading: re"^(((?:(?:[^\n]+)\n)+) {0,3}(=|-)+ *(?:\n+|$))",
  MarkdownTokenType.ThematicBreak: re"^ {0,3}([-*_])(?: *\1){2,} *(?:\n+|$)",
  MarkdownTokenType.IndentedBlockCode: re"^(( {4}[^\n]+\n*)+)",
  MarkdownTokenType.FencingBlockCode: re"^( *`{3,} *([^`\s]+)? *\n([\s\S]+?)\s*`{3} *(\n+|$))",
  MarkdownTokenType.BlockQuote: re"^(( *>[^\n]*(\n[^\n]+)*\n*)+)",
  MarkdownTokenType.Paragraph: re(
    r"^(((?:[^\n]+\n?" &
    r"(?!" &
    r" {0,3}[-*_](?: *[-*_]){2,} *(?:\n+|$)|" & # ThematicBreak
    r"( *>[^\n]+(\n[^\n]+)*\n*)+" & # blockquote
    r"))+)\n*)"
  ),
  MarkdownTokenType.ListBlock: re(
    r"^(" & # group 0 is itself.
    r"( *)(?=[*+-]|\d+\.)" & # set group 1 to indent.
    r"(([*+-])?(?:\d+\.)?) " & # The leading of the indent is list mark `* `, `- `, `+ `, and `1. `.
    r"[\s\S]+?" & # first list item content (optional).
    r"(?:" & # support below block prepending the list block (non-capturing).
    r"\n+(?=\1?(?:[-*_] *){3,}(?:\n+|$))" & # ThematicBreak
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
  MarkdownTokenType.DefineFootnote: re(
    r"^(\[\^([^\]]+)\]: *(" &
    r"[^\n]*(?:\n+|$)" &
    r"(?: {1,}[^\n]*(?:\n+|$))*" &
    r"))"
  ),
  MarkdownTokenType.HTMLBlock: re(
    r"^(" &
    r" *(?:" &
    r"<!--[\s\S]*?-->" &
    r"|<(" & blockTag & r")((?:" & blockTagAttribute & r")*?)>([\s\S]*?)<\/\2>" &
    r"|<" & blockTag & r"(?:" & blockTagAttribute & r")*?\s*\/?>" &
    r")" &
    r" *(?:\n{2,}|\s*$)" &
    r")"
  ),
  MarkdownTokenType.HTMLTable: re(
    r"^( *\|(.+)\n *\|( *[-:]+[-| :]*)\n((?: *\|.*(?:\n|$))*)\n*)"
  ),
  MarkdownTokenType.Text: re"^([^\n]+)",
  MarkdownTokenType.Newline: re"^(\n+)",
  MarkdownTokenType.AutoLink: re"^<([^ >]+(@|:)[^ >]+)>",
  MarkdownTokenType.InlineText: re"^([\s\S]+?(?=[\\<!\[_*`~]|https?://| {2,}\n|$))",
  MarkdownTokenType.InlineEscape: re(
    r"^\\([\\`*{}\[\]()#+\-.!_<>~|])"
  ),
  MarkdownTokenType.InlineHTML: re(
    r"^(" &
    r"<!--[\s\S]*?-->" &
    r"|<(\w+" & r"(?!:/|[^\w\s@]*@)\b" & r")((?:" & blockTagAttribute & r")*?)\s*>([\s\S]*?)<\/\2>" &
    r"|<\w+" & r"(?!:/|[^\w\s@]*@)\b" & r"(?:" & blockTagAttribute & r")*?\s*\/?>" &
    r")"
  ),
  MarkdownTokenType.InlineLink: re(
    r"^(!?\[" &
    r"((?:\[[^^\]]*\]|[^\[\]]|\](?=[^\[]*\]))*)" &
    r"\]\(" &
    r"\s*(<)?([\s\S]*?)(?(3)>)(?:\s+['""]([\s\S]*?)['""])?\s*" &
    r"\))"
  ),
  MarkdownTokenType.InlineRefLink: re(
    r"^(!?\[" &
    r"((?:\[[^^\]]*\]|[^\[\]]|\](?=[^\[]*\]))*)" &
    r"\]\s*\[([^^\]]*)\])"
  ),
  MarkdownTokenType.InlineNoLink: re"^(!?\[((?:\[[^\]]*\]|[^\[\]])*)\])",
  MarkdownTokenType.InlineURL: re(
    """^(https?:\/\/[^\s<]+[^<.,:;"')\]\s])"""
  ),
  MarkdownTokenType.InlineDoubleEmphasis: re(
    r"^(_{2}([\S]+?)_{2}(?!_)" &
    r"|\*{2}([\S]+?)\*{2}(?!\*))"
  ),
  MarkdownTokenType.InlineEmphasis: re(
    r"^(_([\s\S]+?)_(?!_)" &
    r"|\*([\s\S]+?)\*(?!\*))"
  ),
  MarkdownTokenType.InlineCode: re"^((`+)\s*([\s\S]*?[^`])\s*\2(?!`))",
  MarkdownTokenType.InlineBreak: re"^((?: {2,}\n|\\\n)(?!\s*$))",
  MarkdownTokenType.InlineStrikethrough: re"^(~~(?=\S)([\s\S]*?\S)~~)",
  MarkdownTokenType.InlineFootnote: re"^(\[\^([^\]]+)\])",
}.newTable

let blockParsingOrder = @[
  MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  MarkdownTokenType.BlockQuote,
  MarkdownTokenType.Heading,
  MarkdownTokenType.SetextHeading,
  MarkdownTokenType.ThematicBreak,
  MarkdownTokenType.ListBlock,
  MarkdownTokenType.DefineLink,
  MarkdownTokenType.DefineFootnote,
  MarkdownTokenType.HTMLBlock,
  MarkdownTokenType.HTMLTable,
  MarkdownTokenType.Paragraph,
  MarkdownTokenType.Newline,
]

let listParsingOrder = @[
  MarkdownTokenType.Newline,
  MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  MarkdownTokenType.Heading,
  MarkdownTokenType.ThematicBreak,
  MarkdownTokenType.BlockQuote,
  MarkdownTokenType.ListBlock,
  MarkdownTokenType.HTMLBlock,
  MarkdownTokenType.Text,
]

let inlineParsingOrder = @[
  MarkdownTokenType.InlineEscape,
  MarkdownTokenType.InlineHTML,
  MarkdownTokenType.InlineLink,
  MarkdownTokenType.InlineFootnote,
  MarkdownTokenType.InlineRefLink,
  MarkdownTokenType.InlineNoLink,
  MarkdownTokenType.InlineURL,
  MarkdownTokenType.InlineDoubleEmphasis,
  MarkdownTokenType.InlineEmphasis,
  MarkdownTokenType.InlineCode,
  MarkdownTokenType.InlineBreak,
  MarkdownTokenType.InlineStrikethrough,
  MarkdownTokenType.AutoLink,
  MarkdownTokenType.InlineText,
]

proc findToken*(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef;
proc renderToken*(ctx: MarkdownContext, token: MarkdownTokenRef): string;

proc preprocessing*(doc: string): string =
  ## Pre-processing the text.
  result = doc.replace(re"\r\n|\r", "\n")
  result = result.replace(re"^\t", "    ")
  result = result.replace(re"^ {1,3}\t", "    ")
  result = result.replace("\u2424", " ")
  result = result.replace("\u0000", "\uFFFD")
  result = result.replace(re(r"^ +$", {RegexFlag.reMultiLine}), "")

proc escapeTag*(doc: string): string =
  ## Replace `<` and `>` to HTML-safe characters.
  ## Example::
  ##     check escapeTag("<tag>") == "&lt;tag&gt;"
  result = doc.replace("<", "&lt;")
  result = result.replace(">", "&gt;")

proc escapeQuote*(doc: string): string =
  ## Replace `"` to HTML-safe characters.
  ## Example::
  ##     check escapeTag("'tag'") == "&quote;tag&quote;"
  doc.replace("\"", "&quot;")

proc escapeAmpersandChar*(doc: string): string =
  ## Replace character `&` to HTML-safe characters.
  ## Example::
  ##     check escapeAmpersandChar("&amp;") ==  "&amp;amp;"
  result = doc.replace("&", "&amp;")

let reAmpersandSeq = re"&(?!#?\w+;)"

proc escapeAmpersandSeq*(doc: string): string =
  ## Replace `&` from a sequence of characters starting from it to HTML-safe characters.
  ## It's useful to keep those have been escaped.
  ##
  ## Example::
  ##     check escapeAmpersandSeq("&") == "&"
  ##     escapeAmpersandSeq("&amp;") == "&amp;"
  result = doc.replace(sub=reAmpersandSeq, by="&amp;")

proc escapeCode*(doc: string): string =
  ## Make code block in markdown document HTML-safe.
  result = doc.strip(leading=false, trailing=true).escapeTag.escapeAmpersandSeq

proc slugify*(doc: string): string =
  ## Convert the footnote key to a url-friendly key.
  result = doc.toLower.escapeAmpersandSeq.escapeTag.escapeQuote.replace(re"\s+", "-")

iterator parseTokens*(doc: string, typeset: seq[MarkdownTokenType]): MarkdownTokenRef =
  ## Parse markdown document into a sequence of tokens.
  var n = 0
  while n < doc.len:
    var token: MarkdownTokenRef = nil
    for type in typeset:
      token = findToken(doc, n, type)
      if token != nil:
        yield token
        break
    if token == nil:
      raise newException(MarkdownError, fmt"unknown block rule at position {n}.")

proc genNewlineToken(matches: openArray[string]): MarkdownTokenRef =
  if matches[0].len > 1:
    result = MarkdownTokenRef(type: MarkdownTokenType.Newline, newlineVal: matches[0])

proc genHeading(matches: openArray[string], ): MarkdownTokenRef =
  var val: Heading
  val.level = matches[0].len
  if matches[2] =~ re"#+": # ATX headings can be empty. Ignore closing sequence if captured.
    val.inlines = @[]
  else:
    val.inlines = toSeq(parseTokens(matches[2], inlineParsingOrder))
  result = MarkdownTokenRef(type: MarkdownTokenType.Heading, headingVal: val) 

proc genSetextHeading(matches: openArray[string]): MarkdownTokenRef =
  var val: Heading
  if matches[2] == "-":
    val.level = 2
  elif matches[2] == "=":
    val.level = 1
  else:
    raise newException(MarkdownError, fmt"unknown setext heading mark: {matches[2]}")

  val.inlines = toSeq(parseTokens(matches[1].strip, inlineParsingOrder))
  return MarkdownTokenRef(type: MarkdownTokenType.SetextHeading, setextHeadingVal: val) 

proc genThematicBreakToken(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.ThematicBreak, thematicBreakVal: "")

proc genBlockQuoteToken(matches: openArray[string]): MarkdownTokenRef =
  var quote = matches[0].replace(re(r"^ *> ?", {RegexFlag.reMultiLine}), "").strip(chars={'\n', ' '})
  var tokens = toSeq(parseTokens(quote, blockParsingOrder))
  var blockquote = BlockQuote(blocks: tokens)
  result = MarkdownTokenRef(type: MarkdownTokenType.BlockQuote, blockQuoteVal: blockquote)

proc genIndentedBlockCode(matches: openArray[string]): MarkdownTokenRef =
  var code = matches[0].replace(re(r"^ {4}", {RegexFlag.reMultiLine}), "")
  result = MarkdownTokenRef(type: MarkdownTokenType.IndentedBlockCode, codeVal: code)

proc genFencingBlockCode(matches: openArray[string]): MarkdownTokenRef =
  var val: Fence
  val.lang = matches[1]
  val.code = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.FencingBlockCode, fencingBlockCodeVal: val)

proc genParagraph(matches: openArray[string]): MarkdownTokenRef =
  var doc = matches[0].strip(chars={'\n', ' '}).replace(re"\n *", "\n")
  var tokens = toSeq(parseTokens(doc, inlineParsingOrder))
  var val = Paragraph(inlines: tokens)
  result = MarkdownTokenRef(type: MarkdownTokenType.Paragraph, paragraphVal: val)

proc genText(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.Text, textVal: matches[0])

proc genDefineLink(matches: openArray[string]): MarkdownTokenRef =
  var val: DefineLink
  val.text = matches[1]
  val.link = matches[2]
  val.title = matches[3]
  result = MarkdownTokenRef(type: MarkdownTokenType.DefineLink, defineLinkVal: val)

proc genDefineFootnote(matches: openArray[string]): MarkdownTokenRef =
  var val: DefineFootnote
  val.anchor = matches[1]
  val.footnote = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.DefineFootnote, defineFootnoteVal: val)

iterator parseListTokens(doc: string): MarkdownTokenRef =
  let items = doc.findAll(blockRules[MarkdownTokenType.ListItem])
  for index, item in items:
    var val: ListItem
    var text = item.replace(re"^ *(?:[*+-]|\d+\.) +", "").strip
    val.blocks = toSeq(parseTokens(text, listParsingOrder))
    yield MarkdownTokenRef(len: 1, type: MarkdownTokenType.ListItem, listItemVal: val)

proc genListBlock(matches: openArray[string]): MarkdownTokenRef =
  var val: ListBlock
  let doc = matches[0]
  val.ordered = matches[2] =~ re"\d+."
  val.blocks = toSeq(parseListTokens(doc))
  result = MarkdownTokenRef(type: MarkdownTokenType.ListBlock, listBlockVal: val)

proc genHTMLBlock(matches: openArray[string]): MarkdownTokenRef =
  var val: HTMLBlock
  if matches[1] == "":
    val.tag = ""
    val.attributes = ""
    val.text = matches[0].strip
  else:
    val.tag = matches[1].strip
    val.attributes = matches[2].strip
    val.text = matches[3]
  result = MarkdownTokenRef(type: MarkdownTokenType.HTMLBlock, htmlBlockVal: val)

proc findAlign(align: string): seq[string] =
  for cellAlign in align.replace(re"\| *$", "").split(re" *\| *"):
    if cellAlign.find(re"^ *-+: *$") != -1:
      result.add("right")
    elif cellAlign.find(re"^ *:-+: *$") != -1:
      result.add("center")
    elif cellAlign.find(re"^ *:-+ *$") != -1:
      result.add("left")
    else:
      result.add("")

proc genHTMLTable*(matches: openArray[string]): MarkdownTokenRef =
  var head: TableHead
  var headTokens = matches[1].replace(re"^ *| *\| *$", "").split(re" *\| *")
  var aligns = findAlign(matches[2])
  head.cells = newSeq[TableCell](len(headTokens))
  for index, headCell in headTokens:
    head.cells[index].align = aligns[index]
    head.cells[index].dom = toSeq(parseTokens(headCell, inlineParsingOrder))

  var bodyItems = matches[3].replace(re"\n$", "").split("\n")
  var body = newSeq[TableRow](bodyItems.len)
  for i, row in bodyItems:
    var rowCells = row.replace(re"^ *\| *| *\| *$", "").split(re" *(?<!\\)\| *")
    body[i].cells = newSeq[TableCell](rowCells.len)
    for j, rowItem in rowCells:
      body[i].cells[j] = TableCell(dom: toSeq(parseTokens(rowItem.replace(re"\\\\\|", "|"), inlineParsingOrder)))

  var val = HTMLTable(head: head, body: body)
  result = MarkdownTokenRef(type: MarkdownTokenType.HTMLTable, htmlTableVal: val)

proc genAutoLink(matches: openArray[string]): MarkdownTokenRef =
  var link: Link
  link.url = matches[0]
  link.text = matches[0]
  link.isEmail = matches[1] == "@"
  link.isImage = false
  result = MarkdownTokenRef(type: MarkdownTokenType.AutoLink, autoLinkVal: link)

proc genInlineText(matches: openArray[string]): MarkdownTokenRef =
  var text = matches[0].replace(re" *\n", "\n")
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: text)

proc genInlineEscape(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineEscape, inlineEscapeVal: matches[0])

proc genInlineLink(matches: openArray[string]): MarkdownTokenRef =
  var link: Link
  link.isEmail = false
  link.isImage = matches[0][0] == '!'
  link.text = matches[1]
  link.url = matches[3]
  link.title = matches[4]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineLink, inlineLinkVal: link)

proc genInlineHTML(matches: openArray[string]): MarkdownTokenRef =
  var val: HTMLBlock
  if matches[1] == "":
    val.tag = ""
    val.attributes = ""
    val.text = matches[0].strip
  else:
    val.tag = matches[1].strip
    val.attributes = matches[2].strip
    val.text = matches[3]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineHTML, inlineHTMLVal: val)

proc genInlineRefLink(matches: openArray[string]): MarkdownTokenRef =
  var link: RefLink
  link.id = matches[1]
  link.text = matches[2]
  link.isImage = matches[0][0] == '!'
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineRefLink, inlineRefLinkVal: link)

proc genInlineNoLink(matches: openArray[string]): MarkdownTokenRef =
  var link: RefLink
  link.id = matches[1]
  link.text = matches[1]
  link.isImage = matches[0][0] == '!'
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineNoLink, inlineNoLinkVal: link)

proc genInlineURL(matches: openArray[string]): MarkdownTokenRef =
  let url = matches[0]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineURL, inlineURLVal: url)

proc genInlineDoubleEmphasis(matches: openArray[string]): MarkdownTokenRef =
  var text: string
  if matches[0][0] == '_':
    text = matches[1]
  else:
    text = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineDoubleEmphasis, inlineDoubleEmphasisVal: text)

proc genInlineEmphasis(matches: openArray[string]): MarkdownTokenRef =
  var text: string
  if matches[0][0] == '_':
    text = matches[1]
  else:
    text = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineEmphasis, inlineEmphasisVal: text)

proc genInlineCode(matches: openArray[string]): MarkdownTokenRef =
  var code = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineCode, inlineCodeVal: code)

proc genInlineBreak(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineBreak, inlineBreakVal: "")

proc genInlineStrikethrough(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineStrikethrough, inlineStrikethroughVal: matches[1])

proc genInlineFootnote(matches: openArray[string]): MarkdownTokenRef =
  let footnote = RefFootnote(anchor: matches[1])
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineFootnote, inlineFootnoteVal: footnote)

proc findToken(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef =
  ## Find a markdown token from document `doc` at position `start`,
  ## based on a rule type and regex rule.
  let regex = blockRules[ruleType]
  var matches: array[5, string]

  let size = doc[start .. doc.len - 1].matchLen(regex, matches=matches)
  if size == -1:
    return nil
    
  case ruleType
  of MarkdownTokenType.Newline: result = genNewlineToken(matches)
  of MarkdownTokenType.Heading: result = genHeading(matches)
  of MarkdownTokenType.SetextHeading: result = genSetextHeading(matches)
  of MarkdownTokenType.ThematicBreak: result = genThematicBreakToken(matches)
  of MarkdownTokenType.BlockQuote: result = genBlockQuoteToken(matches)
  of MarkdownTokenType.IndentedBlockCode: result = genIndentedBlockCode(matches)
  of MarkdownTokenType.FencingBlockCode: result = genFencingBlockCode(matches)
  of MarkdownTokenType.DefineLink: result = genDefineLink(matches)
  of MarkdownTokenType.DefineFootnote: result = genDefineFootnote(matches)
  of MarkdownTokenType.HTMLBlock: result = genHTMLBlock(matches)
  of MarkdownTokenType.HTMLTable: result = genHTMLTable(matches)
  of MarkdownTokenType.ListBlock: result = genListBlock(matches)
  of MarkdownTokenType.Paragraph: result = genParagraph(matches)
  of MarkdownTokenType.Text: result = genText(matches)
  of MarkdownTokenType.AutoLink: result = genAutoLink(matches)
  of MarkdownTokenType.InlineText: result = genInlineText(matches)
  of MarkdownTokenType.InlineEscape: result = genInlineEscape(matches)
  of MarkdownTokenType.InlineHTML: result = genInlineHTML(matches)
  of MarkdownTokenType.InlineLink: result = genInlineLink(matches)
  of MarkdownTokenType.InlineRefLink: result = genInlineRefLink(matches)
  of MarkdownTokenType.InlineNoLink: result = genInlineNoLink(matches)
  of MarkdownTokenType.InlineURL: result = genInlineURL(matches)
  of MarkdownTokenType.InlineDoubleEmphasis: result = genInlineDoubleEmphasis(matches)
  of MarkdownTokenType.InlineEmphasis: result = genInlineEmphasis(matches)
  of MarkdownTokenType.InlineCode: result = genInlineCode(matches)
  of MarkdownTokenType.InlineBreak: result = genInlineBreak(matches)
  of MarkdownTokenType.InlineStrikethrough: result = genInlineStrikethrough(matches)
  of MarkdownTokenType.InlineFootnote: result = genInlineFootnote(matches)
  else:
    result = genText(matches)

  start += size

proc renderHeading(ctx: MarkdownContext, heading: Heading): string =
  # Render heading tag, for example, `<h1>`, `<h2>`, etc.
  result = fmt"<h{heading.level}>"
  for token in heading.inlines:
    result &= renderToken(ctx, token)
  result &= fmt"</h{heading.level}>"

proc renderText(ctx: MarkdownContext, text: string): string =
  # Render text by escaping itself.
  if ctx.config.escape:
    result = text.escapeAmpersandSeq.escapeTag.escapeQuote
  else:
    result = text

proc renderFencingBlockCode(fence: Fence): string =
  # Render fencing block code
  result = fmt("<pre><code lang=\"{fence.lang}\">{escapeCode(fence.code)}</code></pre>")

proc renderIndentedBlockCode(code: string): string =
  # Render indented block code.
  # The code content will be escaped as it might contains HTML tags.
  # By default the indented block code doesn't support code highlight.
  result = fmt"<pre><code>{escapeCode(code)}</code></pre>"

proc renderParagraph(ctx: MarkdownContext, paragraph: Paragraph): string =
  for token in paragraph.inlines:
    result &= renderToken(ctx, token)
  result = fmt"<p>{result}</p>"

proc renderThematicBreak(): string =
  result = "<hr />"

proc renderBlockQuote(ctx: MarkdownContext, blockQuote: BlockQuote): string =
  result = "<blockquote>"
  for token in blockQuote.blocks:
    result &= renderToken(ctx, token)
  result &= "</blockquote>"

proc renderListItem(ctx: MarkdownContext, listItem: ListItem): string =
  for el in listItem.blocks:
    result &= renderToken(ctx, el)
  result = fmt"<li>{result}</li>"

proc renderListBlock(ctx: MarkdownContext, listBlock: ListBlock): string =
  result = ""
  for el in listBlock.blocks:
    result &= renderListItem(ctx, el.listItemVal)
  if listBlock.ordered:
    result = fmt"<ol>{result}</ol>"
  else:
    result = fmt"<ul>{result}</ul>"

proc escapeInvalidHTMLTag(doc: string): string =
  doc.replace(
    re(r"<(title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)>",
      {RegexFlag.reIgnoreCase}),
    "&lt;\1>")

proc renderHTMLBlock(ctx: MarkdownContext, htmlBlock: HTMLBlock): string =
  var text = htmlBlock.text.escapeInvalidHTMLTag
  if htmlBlock.tag == "":
    result = text
  else:
    var space: string
    if htmlBlock.attributes == "":
      space = ""
    else:
      space = " "
    result = fmt"<{htmlBlock.tag}{space}{htmlBlock.attributes}>{text}</{htmlBlock.tag}>"
  if not ctx.config.keepHTML:
    result = result.escapeAmpersandSeq.escapeTag

proc renderHTMLTableCell(ctx: MarkdownContext, cell: TableCell, tag: string): string =
  if cell.align != "":
    result = fmt"<{tag} style=""text-align: {cell.align}"">"
  else:
    result = fmt"<{tag}>"
  for token in cell.dom:
    result &= renderToken(ctx, token)
  result &= fmt"</{tag}>"

proc renderHTMLTable*(ctx: MarkdownContext, table: HTMLTable): string =
  result &= "<table>"
  result &= "<thead>"
  result &= "<tr>"
  for headCell in table.head.cells:
    result &= renderHTMLTableCell(ctx, headCell, tag="th")
  result &= "</tr>"
  result &= "</thead>"
  result &= "<tbody>"
  for row in table.body:
    result &= "<tr>"
    for cell in row.cells:
      result &= renderHTMLTableCell(ctx, cell, tag="td")
    result &= "</tr>"
  result &= "</tbody>"
  result &= "</table>"

proc renderInlineEscape(ctx: MarkdownContext, inlineEscape: string): string =
  result = inlineEscape.escapeAmpersandSeq.escapeTag.escapeQuote

proc renderInlineText(ctx: MarkdownContext, inlineText: string): string =
  if ctx.config.escape:
    result = renderInlineEscape(ctx, inlineText)
  else:
    result = inlineText

proc renderAutoLink(ctx: MarkdownContext, link: Link): string =
  if link.isEmail:
    result = fmt"""<a href="mailto:{link.url}">{link.text}</a>"""
  else:
    result = fmt"""<a href="{link.url}">{link.text}</a>"""

proc renderInlineLink(ctx: MarkdownContext, link: Link): string =
  if link.isImage:
    result = fmt"""<img src="{link.url}" alt="{link.text}">"""
  else:
    result = fmt"""<a href="{link.url}" title="{link.title}">{link.text}</a>"""

proc renderInlineRefLink(ctx: MarkdownContext, link: RefLink): string =
  if ctx.links.hasKey(link.id):
    let definedLink = ctx.links[link.id]
    if definedLink.isImage:
      result = fmt"""<img src="{definedLink.url}" alt="{link.text}">"""
    else:
      result = fmt"""<a href="{definedLink.url}" title="{definedLink.title}">{link.text}</a>"""
  else:
    result = fmt"[{link.id}][{link.text}]"

proc renderInlineURL(ctx: MarkdownContext, url: string): string =
  result = fmt"""<a href="{url}">{url}</a>"""

proc renderInlineDoubleEmphasis(ctx: MarkdownContext, text: string): string =
  result = fmt"""<strong>{text}</strong>"""

proc renderInlineEmphasis(ctx: MarkdownContext, text: string): string =
  # TODO: move to phase 2
  var em = ""
  for token in parseTokens(text, inlineParsingOrder):
    em &= renderToken(ctx, token)
  result = fmt"""<em>{em}</em>"""

proc renderInlineCode(ctx: MarkdownContext, code: string): string =
  let formattedCode = code.strip.escapeAmpersandChar.escapeTag.replace(re" *\n", " ")
  result = fmt"""<code>{formattedCode}</code>"""

proc renderInlineBreak(ctx: MarkdownContext, code: string): string =
  result = "<br />\n"

proc renderInlineStrikethrough(ctx: MarkdownContext, text: string): string =
  result = fmt"<del>{text}</del>"

proc renderInlineFootnote(ctx: MarkdownContext, footnote: RefFootnote): string =
  let slug = slugify(footnote.anchor)
  result = fmt"""<sup class="footnote-ref" id="footnote-ref-{slug}">""" &
    fmt"""<a href="#footnote-{slug}">{footnote.anchor}</a></sup>"""

proc renderToken*(ctx: MarkdownContext, token: MarkdownTokenRef): string =
  ## Render token.
  ## This is a simple dispatcher function.
  case token.type
  of MarkdownTokenType.Heading: result = renderHeading(ctx, token.headingVal)
  of MarkdownTokenType.SetextHeading: result = renderHeading(ctx, token.setextHeadingVal)
  of MarkdownTokenType.ThematicBreak: result = renderThematicBreak()
  of MarkdownTokenType.Text: result = renderText(ctx, token.textVal)
  of MarkdownTokenType.IndentedBlockCode: result = renderIndentedBlockCode(token.codeVal)
  of MarkdownTokenType.FencingBlockCode: result = renderFencingBlockCode(token.fencingBlockCodeVal)
  of MarkdownTokenType.Paragraph: result = renderParagraph(ctx, token.paragraphVal)
  of MarkdownTokenType.BlockQuote: result = renderBlockQuote(ctx, token.blockQuoteVal)
  of MarkdownTokenType.ListBlock: result = renderListBlock(ctx, token.listBlockVal)
  of MarkdownTokenType.ListItem: result = renderListItem(ctx, token.listItemVal)
  of MarkdownTokenType.HTMLBlock: result = renderHTMLBlock(ctx, token.htmlBlockVal)
  of MarkdownTokenType.HTMLTable: result = renderHTMLTable(ctx, token.htmlTableVal)
  of MarkdownTokenType.InlineText: result = renderInlineText(ctx, token.inlineTextVal)
  of MarkdownTokenType.InlineEscape: result = renderInlineEscape(ctx, token.inlineEscapeVal)
  of MarkdownTokenType.AutoLink: result = renderAutoLink(ctx, token.autoLinkVal)
  of MarkdownTokenType.InlineHTML: result = renderHTMLBlock(ctx, token.inlineHTMLVal)
  of MarkdownTokenType.InlineLink: result = renderInlineLink(ctx, token.inlineLinkVal)
  of MarkdownTokenType.InlineRefLink: result = renderInlineRefLink(ctx, token.inlineRefLinkVal)
  of MarkdownTokenType.InlineNoLink: result = renderInlineRefLink(ctx, token.inlineNoLinkVal)
  of MarkdownTokenType.InlineURL: result = renderInlineURL(ctx, token.inlineURLVal)
  of MarkdownTokenType.InlineDoubleEmphasis: result = renderInlineDoubleEmphasis(ctx, token.inlineDoubleEmphasisVal)
  of MarkdownTokenType.InlineEmphasis: result = renderInlineEmphasis(ctx, token.inlineEmphasisVal)
  of MarkdownTokenType.InlineCode: result = renderInlineCode(ctx, token.inlineCodeVal)
  of MarkdownTokenType.InlineBreak: result = renderInlineBreak(ctx, token.inlineBreakVal)
  of MarkdownTokenType.InlineStrikethrough: result = renderInlineStrikethrough(ctx, token.inlineStrikethroughVal)
  of MarkdownTokenType.InlineFootnote: result = renderInlineFootnote(ctx, token.inlineFootnoteVal)
  else:
    result = ""

proc buildContext(tokens: seq[MarkdownTokenRef], config: MarkdownConfig): MarkdownContext =
  # add building context
  result = MarkdownContext(
    links: initTable[string, Link](),
    footnotes: initTable[string, string](),
    config: config
  )
  for token in tokens:
    case token.type
    of MarkdownTokenType.DefineLink:
      result.links[token.defineLinkVal.text] = Link(
        url: token.defineLinkVal.link,
        text: token.defineLinkVal.text,
        title: token.defineLinkVal.title)
    of MarkdownTokenType.DefineFootnote:
      result.footnotes[token.defineFootnoteVal.anchor] = token.defineFootnoteVal.footnote
    else:
      discard

proc markdown*(doc: string, config: MarkdownConfig = initMarkdownConfig()): string =
  ## Convert markdown string `doc` into an HTML string. Parsing & rendering
  ## behavior can be customized using ``config`` - see `MarkdownConfig <#MarkdownConfig>`_
  ## for the available options.
  let tokens = toSeq(parseTokens(preprocessing(doc), blockParsingOrder))
  let ctx = buildContext(tokens, config)
  for token in tokens:
      result &= renderToken(ctx, token)

proc readCLIOptions*(): MarkdownConfig =
  ## Read options from command line.
  ## If no option passed, the corresponding option will be the default.
  ##
  ## Available options:
  ## * `-e` / `--escape`
  ## * `--no-escape`
  ## * `-k` / `--keep-html`
  ## * '--no-keep-html`
  ##
  result = initMarkdownConfig()
  when declared(commandLineParams):
    for opt in commandLineParams():
      case opt
      of "--escape": result.escape = true
      of "-e": result.escape = true
      of "--no-escape": result.escape = false
      of "--keep-html": result.keepHTML = true
      of "-k": result.keepHTML = true
      of "--no-keep-html": result.keepHTML = false
      else: discard

when isMainModule:
  stdout.write(markdown(stdin.readAll, config=readCLIOptions()))

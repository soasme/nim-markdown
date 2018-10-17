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
    footnotes: Table[string, string]
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

  # Type for defining footnote
  DefineFootnote* = object
    anchor: string
    footnote: string

  HTMLBlock* = object
    tag: string
    attributes: string
    text: string

  Paragraph* = object
    dom: iterator(): MarkdownTokenRef

  Link* = object
    url: string
    text: string
    isImage: bool
    isEmail: bool

  RefLink* = object
    id: string
    text: string
    isImage: bool

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
    DefineFootnote,
    HTMLBlock,
    Newline,
    AutoLink,
    InlineEscape,
    InlineText,
    InlineHTML,
    InlineLink,
    InlineRefLink,
    InlineNoLink,
    InlineURL,
    InlineDoubleEmphasis

  # Hold two values: type: MarkdownTokenType, and xyzValue.
  # xyz is the particular type name.
  MarkdownTokenRef* = ref MarkdownToken
  MarkdownToken* = object
    len: int
    case type*: MarkdownTokenType
    of MarkdownTokenType.Header: headerVal*: Header
    of MarkdownTokenType.Hrule: hruleVal*: string
    of MarkdownTokenType.BlockQuote: blockQuoteVal*: string
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
    of MarkdownTokenType.InlineHTML: inlineHTMLVal*: HTMLBlock
    of MarkdownTokenType.InlineLink: inlineLinkVal*: Link
    of MarkdownTokenType.InlineRefLink: inlineRefLinkVal*: RefLink
    of MarkdownTokenType.InlineNoLink: inlineNoLinkVal*: RefLink
    of MarkdownTokenType.InlineURL: inlineURLVal*: string
    of MarkdownTokenType.InlineDoubleEmphasis: inlineDoubleEmphasisVal*: string

const INLINE_TAGS = [
    "a", "em", "strong", "small", "s", "cite", "q", "dfn", "abbr", "data",
    "time", "code", "var", "samp", "kbd", "sub", "sup", "i", "b", "u", "mark",
    "ruby", "rt", "rp", "bdi", "bdo", "span", "br", "wbr", "ins", "del",
    "img", "font",
]

let blockTagAttribute = """\s*[a-zA-Z\-](?:\s*\=\s*(?:"[^"]*"|'[^']*'|[^\s'">]+))?"""
let blockTag = r"(?!(?:" & fmt"{INLINE_TAGS.join(""|"")}" & r")\b)\w+(?!:/|[^\w\s@]*@)\b"

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
    r"|<(" & blockTag & r")((?:" & blockTagAttribute & r")*?)>([\s\S]*?)<\/\1>" &
    r"|<" & blockTag & r"(?:" & blockTagAttribute & r")*?\s*\/?>" &
    r")" &
    r" *(?:\n{2,}|\s*$)" &
    r")"
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
    r"|<(\w+" & r"(?!:/|[^\w\s@]*@)\b" & r")((?:" & blockTagAttribute & r")*?)\s*>([\s\S]*?)<\/\1>" &
    r"|<\w+" & r"(?!:/|[^\w\s@]*@)\b" & r"(?:" & blockTagAttribute & r")*?\s*\/?>" &
    r")"
  ),
  MarkdownTokenType.InlineLink: re(
    r"^(!?\[" &
    r"((?:\[[^^\]]*\]|[^\[\]]|\](?=[^\[]*\]))*)" &
    r"\]\(" &
    r"\s*([\s\S]*?)" &
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
    r"^(_{2}([\s\S]+?)_{2}(?!_)" &
    r"|\*{2}([\s\S]+?)\*{2}(?!\*))"
  ),
}.newTable

let blockParsingOrder = @[
  MarkdownTokenType.Header,
  MarkdownTokenType.Hrule,
  MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  MarkdownTokenType.BlockQuote,
  MarkdownTokenType.ListBlock,
  MarkdownTokenType.DefineLink,
  MarkdownTokenType.DefineFootnote,
  MarkdownTokenType.HTMLBlock,
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

let inlineParsingOrder = @[
  MarkdownTokenType.InlineEscape,
  MarkdownTokenType.InlineHTML,
  MarkdownTokenType.InlineLink,
  MarkdownTokenType.InlineRefLink,
  MarkdownTokenType.InlineNoLink,
  MarkdownTokenType.InlineURL,
  MarkdownTokenType.InlineDoubleEmphasis,
  MarkdownTokenType.Newline,
  MarkdownTokenType.AutoLink,
  MarkdownTokenType.InlineText,
]

proc findToken(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef;
proc renderToken(ctx: MarkdownContext, token: MarkdownTokenRef): string;

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

iterator parseTokens(doc: string, typeset: seq[MarkdownTokenType]): MarkdownTokenRef =
  # Parse markdown document into a sequence of tokens.
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

# TODO: parse inline items.
# TODO: parse list item tokens.

iterator parseListTokens(doc: string): MarkdownTokenRef =
  let items = doc.findAll(blockRules[MarkdownTokenType.ListItem])
  for index, item in items:
    var val: ListItem
    var text = item.replace(re"^ *(?:[*+-]|\d+\.) +", "")
    val.doc = MarkdownTokenRef(len: item.len, type: MarkdownTokenType.Text, textVal: text)
    yield MarkdownTokenRef(len: 1, type: MarkdownTokenType.ListItem, listItemVal: val)

proc genNewlineToken(matches: openArray[string]): MarkdownTokenRef =
  if matches[0].len > 1:
    result = MarkdownTokenRef(type: MarkdownTokenType.Newline, newlineVal: matches[0])

proc genHeaderToken(matches: openArray[string], ): MarkdownTokenRef =
  var val: Header
  val.level = matches[0].len
  val.doc = matches[1]
  result = MarkdownTokenRef(type: MarkdownTokenType.Header, headerVal: val) 

proc genHruleToken(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.Hrule, hruleVal: "")

proc genBlockQuoteToken(matches: openArray[string]): MarkdownTokenRef =
  var quote = matches[0].replace(re(r"^ *> ?", {RegexFlag.reMultiLine}), "").strip(chars={'\n', ' '})
  result = MarkdownTokenRef(type: MarkdownTokenType.BlockQuote, blockQuoteVal: quote)

proc genIndentedBlockCode(matches: openArray[string]): MarkdownTokenRef =
  var code = matches[0].replace(re(r"^ {4}", {RegexFlag.reMultiLine}), "")
  result = MarkdownTokenRef(type: MarkdownTokenType.IndentedBlockCode, codeVal: code)

proc genFencingBlockCode(matches: openArray[string]): MarkdownTokenRef =
  var val: Fence
  val.lang = matches[1]
  val.code = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.FencingBlockCode, fencingBlockCodeVal: val)

proc genParagraph(matches: openArray[string]): MarkdownTokenRef =
  var doc = matches[0].strip(chars={'\n', ' '})
  var tokens = iterator(): MarkdownTokenRef =
    for token in parseTokens(doc, inlineParsingOrder):
      yield token
  var val = Paragraph(dom: tokens)
  result = MarkdownTokenRef(type: MarkdownTokenType.Paragraph, paragraphVal: val)

proc genText(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.Text, textVal: matches[0])

proc genDefineLink(matches: openArray[string]): MarkdownTokenRef =
  var val: DefineLink
  val.text = matches[1]
  val.link = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.DefineLink, defineLinkVal: val)

proc genDefineFootnote(matches: openArray[string]): MarkdownTokenRef =
  var val: DefineFootnote
  val.anchor = matches[1]
  val.footnote = matches[2]
  result = MarkdownTokenRef(type: MarkdownTokenType.DefineFootnote, defineFootnoteVal: val)

proc genListBlock(matches: openArray[string]): MarkdownTokenRef =
  var val: ListBlock
  let doc = matches[0]
  val.ordered = matches[2] =~ re"\d+."
  val.elems = iterator(): ListItem =
    for token in parseListTokens(doc):
      yield ListItem(doc: token)
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

proc genAutoLink(matches: openArray[string]): MarkdownTokenRef =
  var link: Link
  link.url = matches[0]
  link.text = matches[0]
  link.isEmail = matches[1] == "@"
  link.isImage = false
  result = MarkdownTokenRef(type: MarkdownTokenType.AutoLink, autoLinkVal: link)

proc genInlineText(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: matches[0])

proc genInlineEscape(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineEscape, inlineEscapeVal: matches[0])

proc genInlineLink(matches: openArray[string]): MarkdownTokenRef =
  var link: Link
  link.url = matches[2]
  link.text = matches[1]
  link.isEmail = false
  link.isImage = matches[0][0] == '!'
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

proc findToken(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef =
  # Find a markdown token from document `doc` at position `start`,
  # based on a rule type and regex rule.
  let regex = blockRules[ruleType]
  var matches: array[5, string]

  let size = doc[start .. doc.len - 1].matchLen(regex, matches=matches)
  if size == -1:
    return nil

  case ruleType
  of MarkdownTokenType.Newline: result = genNewlineToken(matches)
  of MarkdownTokenType.Header: result = genHeaderToken(matches)
  of MarkdownTokenType.Hrule: result = genHruleToken(matches)
  of MarkdownTokenType.BlockQuote: result = genBlockQuoteToken(matches)
  of MarkdownTokenType.IndentedBlockCode: result = genIndentedBlockCode(matches)
  of MarkdownTokenType.FencingBlockCode: result = genFencingBlockCode(matches)
  of MarkdownTokenType.DefineLink: result = genDefineLink(matches)
  of MarkdownTokenType.DefineFootnote: result = genDefineFootnote(matches)
  of MarkdownTokenType.HTMLBlock: result = genHTMLBlock(matches)
  of MarkdownTokenType.ListItem:
    var val: ListItem
    # TODO: recursively parse val.doc
    val.doc = MarkdownTokenRef(type: MarkdownTokenType.Text, textVal: matches[0])
    result = MarkdownTokenRef(type: MarkdownTokenType.ListItem, listItemVal: val)
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
  else:
    result = genText(matches)

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

proc renderFencingBlockCode*(fence: Fence): string =
  # Render fencing block code
  result = fmt("<pre><code lang=\"{fence.lang}\">{escapeCode(fence.code)}</code></pre>")

proc renderIndentedBlockCode*(code: string): string =
  # Render indented block code.
  # The code content will be escaped as it might contains HTML tags.
  # By default the indented block code doesn't support code highlight.
  result = fmt"<pre><code>{escapeCode(code)}</code></pre>"

proc renderParagraph*(ctx: MarkdownContext, paragraph: Paragraph): string =
  for token in paragraph.dom():
    result &= renderToken(ctx, token)
  result = fmt"<p>{result}</p>"

proc renderHrule(hrule: string): string =
  result = "<hr>"

proc renderBlockQuote(blockQuote: string): string =
  result = fmt"<blockquote>{blockQuote}</blockquote>"


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

proc renderHTMLBlock(ctx: MarkdownContext, htmlBlock: HTMLBlock): string =
  if htmlBlock.tag == "":
    result = htmlBlock.text
  else:
    result = fmt"<{htmlBlock.tag} {htmlBlock.attributes}>{htmlBlock.text}</{htmlBlock.tag}>"

proc renderInlineText(ctx: MarkdownContext, inlineText: string): string =
  result = inlineText

proc renderInlineEscape(ctx: MarkdownContext, inlineEscape: string): string =
  result = inlineEscape.escapeAmpersandSeq.escapeTag

proc renderAutoLink(ctx: MarkdownContext, link: Link): string =
  if link.isEmail:
    result = fmt"""<a href="mailto:{link.url}">{link.text}</a>"""
  else:
    result = fmt"""<a href="{link.url}">{link.text}</a>"""

proc renderInlineLink(ctx: MarkdownContext, link: Link): string =
  if link.isImage:
    result = fmt"""<img src="{link.url}" alt="{link.text}">"""
  else:
    result = fmt"""<a href="{link.url}">{link.text}</a>"""

proc renderInlineRefLink(ctx: MarkdownContext, link: RefLink): string =
  if ctx.links.hasKey(link.id):
    let url = ctx.links[link.id]
    if link.isImage:
      result = fmt"""<img src="{url}" alt="{link.text}">"""
    else:
      result = fmt"""<a href="{url}">{link.text}</a>"""
  else:
    result = fmt"[{link.id}][{link.text}]"

proc renderInlineURL(ctx: MarkdownContext, url: string): string =
  result = fmt"""<a href="{url}">{url}</a>"""

proc renderInlineDoubleEmphasis(ctx: MarkdownContext, text: string): string =
  result = fmt"""<strong>{text}</strong>"""

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
  of MarkdownTokenType.IndentedBlockCode:
    result = renderIndentedBlockCode(token.codeVal)
  of MarkdownTokenType.FencingBlockCode:
    result = renderFencingBlockCode(token.fencingBlockCodeVal)
  of MarkdownTokenType.Paragraph:
    result = renderParagraph(ctx, token.paragraphVal)
  of MarkdownTokenType.BlockQuote:
    result = renderBlockQuote(token.blockQuoteVal)
  of MarkdownTokenType.ListBlock:
    result = renderListBlock(ctx, token.listBlockVal)
  of MarkdownTokenType.ListItem:
    result = renderListItem(ctx, token.listItemVal)
  of MarkdownTokenType.HTMLBlock:
    result = renderHTMLBlock(ctx, token.htmlBlockVal)
  of MarkdownTokenType.InlineText:
    result = renderInlineText(ctx, token.inlineTextVal)
  of MarkdownTokenType.InlineEscape:
    result = renderInlineEscape(ctx, token.inlineEscapeVal)
  of MarkdownTokenType.AutoLink:
    result = renderAutoLink(ctx, token.autoLinkVal)
  of MarkdownTokenType.InlineHTML:
    result = renderHTMLBlock(ctx, token.inlineHTMLVal)
  of MarkdownTokenType.InlineLink:
    result = renderInlineLink(ctx, token.inlineLinkVal)
  of MarkdownTokenType.InlineRefLink:
    result = renderInlineRefLink(ctx, token.inlineRefLinkVal)
  of MarkdownTokenType.InlineNoLink:
    result = renderInlineRefLink(ctx, token.inlineNoLinkVal)
  of MarkdownTokenType.InlineURL:
    result = renderInlineURL(ctx, token.inlineURLVal)
  of MarkdownTokenType.InlineDoubleEmphasis:
    result = renderInlineDoubleEmphasis(ctx, token.inlineDoubleEmphasisVal)
  else:
    result = ""

proc buildContext(tokens: seq[MarkdownTokenRef]): MarkdownContext =
  # add building context
  result = MarkdownContext(links: initTable[string, string](), footnotes: initTable[string, string]())
  for token in tokens:
    case token.type
    of MarkdownTokenType.DefineLink:
      result.links[token.defineLinkVal.text] = token.defineLinkVal.link
    of MarkdownTokenType.DefineFootnote:
      result.footnotes[token.defineFootnoteVal.anchor] = token.defineFootnoteVal.footnote
    else:
      discard

# Turn markdown-formatted string into HTML-formatting string.
# By setting `escapse` to false, no HTML tag will be escaped.
proc markdown*(doc: string, escape: bool = true): string =
  let tokens = toSeq(parseTokens(preprocessing(doc), blockParsingOrder))
  let ctx = buildContext(tokens)
  for token in tokens:
      result &= renderToken(ctx, token)
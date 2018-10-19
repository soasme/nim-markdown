# nim-markdown
#
## A beautiful Markdown parser in the Nim world.
##
## Usage of the binary: convert markdown document in bash like below.::
##
##    $ markdown < file.md > file.html
##
## Usage of the library: import this file by writing `import markdown`.::
##
##     let s = markdown("# hello world")
##     echo(s)
##
## Options are passed as config string. Choices of options are listed below:
##
## * `KeepHTML`, default `false`.
## * `Escape`, default `true`.
##
## With the default option, `Nim & Markdown` will be translated into `Nim &amp; Markdown`.
## If you want to escape no characters in the document, turn off `Escape`::
##
##     let config = """
##     Escape: false
##     """
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
##     let config = """
##     Escape: true
##     """
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

CONST MARKDOWN_VERSION = "0.2.0"

type
  MarkdownError* = object of Exception ## The error object for markdown parsing and rendering.

  Header* = object ## The type for storing header element.
    doc: string
    level: int

  Fence* = object ## The type for fencing block code
    code: string
    lang: string

  ListItem* = object ## The type for the list item
    dom: seq[MarkdownTokenRef]

  ListBlock* = object ## The type for the list block
    elems: seq[MarkdownTokenRef]
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
    dom: iterator(): MarkdownTokenRef

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

  MarkdownContext* = object ## The type for saving parsing context.
    links: Table[string, Link]
    footnotes: Table[string, string]
    escape: bool
    keepHTML: bool
    listDepth: int

  MarkdownTokenType* {.pure.} = enum # All token types
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
  MarkdownTokenType.InlineText: re"^([\s\S]+?(?=[\\<!\[_*`~]|https?://| *\n|$))",
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
    r"^(_{2}([\s\S]+?)_{2}(?!_)" &
    r"|\*{2}([\s\S]+?)\*{2}(?!\*))"
  ),
  MarkdownTokenType.InlineEmphasis: re(
    r"^(_([\s\S]+?)_(?!_)" &
    r"|\*([\s\S]+?)\*(?!\*))"
  ),
  MarkdownTokenType.InlineCode: re"^((`+)\s*([\s\S]*?[^`])\s*\2(?!`))",
  MarkdownTokenType.InlineBreak: re"^( *\n(?!\s*$))",
  MarkdownTokenType.InlineStrikethrough: re"^(~~(?=\S)([\s\S]*?\S)~~)",
  MarkdownTokenType.InlineFootnote: re"^(\[\^([^\]]+)\])",
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
  result = result.replace(re"\t", "    ")
  result = result.replace("\u2424", " ")
  result = result.replace(re(r"^ +$", {RegexFlag.reMultiLine}), "")

proc escapeTag*(doc: string): string =
  ## Replace `<` and `>` to HTML-safe characters.
  ## Example::
  ##     check escapeTag("<tag>") == "&lt;tag&gt;"
  result = doc.replace("<", "&lt;")
  result = result.replace(">", "&gt;")

proc escapeQuote*(doc: string): string =
  ## Replace `'` and `"` to HTML-safe characters.
  ## Example::
  ##     check escapeTag("'tag'") == "&quote;tag&quote;"
  result = doc.replace("'", "&quote;")
  result = result.replace("\"", "&quote;")

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
  result = doc.strip(leading=false, trailing=true).escapeTag.escapeAmpersandChar

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
    val.dom = toSeq(parseTokens(text, listParsingOrder))
    yield MarkdownTokenRef(len: 1, type: MarkdownTokenType.ListItem, listItemVal: val)
    
proc genListBlock(matches: openArray[string]): MarkdownTokenRef =
  var val: ListBlock
  let doc = matches[0]
  val.ordered = matches[2] =~ re"\d+."
  val.elems = toSeq(parseListTokens(doc))
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
  of MarkdownTokenType.Header: result = genHeaderToken(matches)
  of MarkdownTokenType.Hrule: result = genHruleToken(matches)
  of MarkdownTokenType.BlockQuote: result = genBlockQuoteToken(matches)
  of MarkdownTokenType.IndentedBlockCode: result = genIndentedBlockCode(matches)
  of MarkdownTokenType.FencingBlockCode: result = genFencingBlockCode(matches)
  of MarkdownTokenType.DefineLink: result = genDefineLink(matches)
  of MarkdownTokenType.DefineFootnote: result = genDefineFootnote(matches)
  of MarkdownTokenType.HTMLBlock: result = genHTMLBlock(matches)
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

proc renderHeader(header: Header): string =
  # Render header tag, for example, `<h1>`, `<h2>`, etc.
  result = fmt"<h{header.level}>{header.doc}</h{header.level}>"

proc renderText(ctx: MarkdownContext, text: string): string =
  # Render text by escaping itself.
  if ctx.escape:
    result = text.escapeAmpersandSeq.escapeTag
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
  for token in paragraph.dom():
    result &= renderToken(ctx, token)
  result = fmt"<p>{result}</p>"

proc renderHrule(hrule: string): string =
  result = "<hr>"

proc renderBlockQuote(blockQuote: string): string =
  result = fmt"<blockquote>{blockQuote}</blockquote>"

proc renderListItem(ctx: MarkdownContext, listItem: ListItem): string =
  for el in listItem.dom:
    result &= renderToken(ctx, el)
  result = fmt"<li>{result}</li>"

proc renderListBlock(ctx: MarkdownContext, listBlock: ListBlock): string =
  result = ""
  for el in listBlock.elems:
    result &= renderListItem(ctx, el.listItemVal)
  if listBlock.ordered:
    result = fmt"<ol>{result}</ol>"
  else:
    result = fmt"<ul>{result}</ul>"

proc renderHTMLBlock(ctx: MarkdownContext, htmlBlock: HTMLBlock): string =
  if htmlBlock.tag == "":
    result = htmlBlock.text
  else:
    var space: string
    if htmlBlock.attributes == "":
      space = ""
    else:
      space = " "
    result = fmt"<{htmlBlock.tag}{space}{htmlBlock.attributes}>{htmlBlock.text}</{htmlBlock.tag}>"
  if not ctx.keepHTML:
    result = result.escapeAmpersandSeq.escapeTag

proc renderInlineEscape(ctx: MarkdownContext, inlineEscape: string): string =
  result = inlineEscape.escapeAmpersandSeq.escapeTag

proc renderInlineText(ctx: MarkdownContext, inlineText: string): string =
  if ctx.escape:
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
  result = fmt"""<em>{text}</em>"""

proc renderInlineCode(ctx: MarkdownContext, code: string): string =
  let formattedCode = code.strip.escapeAmpersandChar.escapeTag
  result = fmt"""<code>{formattedCode}</code>"""

proc renderInlineBreak(ctx: MarkdownContext, code: string): string =
  result = fmt"<br>"

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
  of MarkdownTokenType.Header: result = renderHeader(token.headerVal)
  of MarkdownTokenType.Hrule: result = renderHrule(token.hruleVal)
  of MarkdownTokenType.Text: result = renderText(ctx, token.textVal)
  of MarkdownTokenType.IndentedBlockCode: result = renderIndentedBlockCode(token.codeVal)
  of MarkdownTokenType.FencingBlockCode: result = renderFencingBlockCode(token.fencingBlockCodeVal)
  of MarkdownTokenType.Paragraph: result = renderParagraph(ctx, token.paragraphVal)
  of MarkdownTokenType.BlockQuote: result = renderBlockQuote(token.blockQuoteVal)
  of MarkdownTokenType.ListBlock: result = renderListBlock(ctx, token.listBlockVal)
  of MarkdownTokenType.ListItem: result = renderListItem(ctx, token.listItemVal)
  of MarkdownTokenType.HTMLBlock: result = renderHTMLBlock(ctx, token.htmlBlockVal)
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

proc needEscape(config: string): bool =
  var matches: array[1, string]
  let pos = config.find(
    re(r"(?:^|\n+)escape:\s*(true|false)(?:\n|$)", {RegexFlag.reIgnoreCase}),
    matches)
  if pos == -1:
    result = false
  elif matches[0] != "true":
    result = false
  else:
    result = true

proc needKeepHTML(config: string): bool =
  var matches: array[1, string]
  let pos = config.find(
    re(r"(?:^|\n+)keephtml:\s*(true|false)(?:\n|$)", {RegexFlag.reIgnoreCase}),
    matches)
  if pos == -1:
    result = false
  elif matches[0] == "true":
    result = true
  else:
    result = false

proc buildContext(tokens: seq[MarkdownTokenRef], config: string): MarkdownContext =
  # add building context
  result = MarkdownContext(
    links: initTable[string, Link](),
    footnotes: initTable[string, string](),
    escape: needEscape(config),
    keepHTML: needKeepHTML(config),
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

proc markdown*(doc: string, config: string = """
Escape: true
KeepHTML: false
"""): string =
  ## Convert markdown string `doc` into an HTML string.
  let tokens = toSeq(parseTokens(preprocessing(doc), blockParsingOrder))
  let ctx = buildContext(tokens, config)
  for token in tokens:
      result &= renderToken(ctx, token)

when isMainModule:
  stdout.write(markdown(stdin.readAll))

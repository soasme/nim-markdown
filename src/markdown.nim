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

import re, strutils, strformat, tables, sequtils, math, uri, htmlparser, lists

const MARKDOWN_VERSION* = "0.4.0"

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
    doc: string
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

  Delimeter* = object
    token: MarkdownTokenRef
    kind: string
    num: int
    originalNum: int
    isActive: bool
    canOpen: bool
    canClose: bool

  Emphasis* = object
    inlines: seq[MarkdownTokenRef]

  DoubleEmphasis* = object
    inlines: seq[MarkdownTokenRef]

  MarkdownConfig* = object ## Options for configuring parsing or rendering behavior.
    escape: bool ## escape ``<``, ``>``, and ``&`` characters to be HTML-safe
    keepHtml: bool ## preserve HTML tags rather than escape it

  MarkdownContext* = object ## The type for saving parsing context.
    links: Table[string, Link]
    footnotes: Table[string, string]
    listDepth: int
    config: MarkdownConfig

  MarkdownTokenType* {.pure.} = enum # All token types
    ATXHeading,
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
    of MarkdownTokenType.ATXHeading: atxHeadingVal*: Heading
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
    of MarkdownTokenType.InlineHTML: inlineHTMLVal*: string
    of MarkdownTokenType.InlineLink: inlineLinkVal*: Link
    of MarkdownTokenType.InlineRefLink: inlineRefLinkVal*: RefLink
    of MarkdownTokenType.InlineNoLink: inlineNoLinkVal*: RefLink
    of MarkdownTokenType.InlineURL: inlineURLVal*: string
    of MarkdownTokenType.InlineDoubleEmphasis: inlineDoubleEmphasisVal*: DoubleEmphasis
    of MarkdownTokenType.InlineEmphasis: inlineEmphasisVal*: Emphasis
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
let TAGNAME = r"[A-Za-z][A-Za-z0-9-]*"
let ATTRIBUTENAME = r"[a-zA-Z_:][a-zA-Z0-9:._-]*"
let UNQUOTEDVALUE = r"[^""'=<>`\x00-\x20]+"
let DOUBLEQUOTEDVALUE = """"[^"]*""""
let SINGLEQUOTEDVALUE = r"'[^']*'"
let ATTRIBUTEVALUE = "(?:" & UNQUOTEDVALUE & "|" & SINGLEQUOTEDVALUE & "|" & DOUBLEQUOTEDVALUE & ")"
let ATTRIBUTEVALUESPEC = r"(?:\s*=" & r"\s*" & ATTRIBUTEVALUE & r")"
let ATTRIBUTE = r"(?:\s+" & ATTRIBUTENAME & ATTRIBUTEVALUESPEC & r"?)"
let OPEN_TAG = r"<" & TAGNAME & ATTRIBUTE & r"*" & r"\s*/?>"
let CLOSE_TAG = r"</" & TAGNAME & r"\s*[>]"
let HTML_COMMENT = r"<!---->|<!--(?:-?[^>-])(?:-?[^-])*-->"
let PROCESSING_INSTRUCTION = r"[<][?].*?[?][>]"
let DECLARATION = r"<![A-Z]+\s+[^>]*>"
let CDATA_SECTION = r"<!\[CDATA\[[\s\S]*?\]\]>"
let HTML_TAG = (
  r"(?:" &
  OPEN_TAG & "|" &
  CLOSE_TAG & "|" &
  HTML_COMMENT & "|" &
  PROCESSING_INSTRUCTION & "|" &
  DECLARATION & "|" &
  CDATA_SECTION &
  & r")"
)

let LINK_SCHEME = r"[a-zA-Z][a-zA-Z0-9+.-]{1,31}"
let LINK_EMAIL = r"[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+(@)[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+(?![-_])"
let LINK_LABEL = r"(?:\[[^\[\]]*\]|\\[\[\]]?|`[^`]*`|[^\[\]\\])*?"
let LINK_HREF = r"\s*(<(?:\\[<>]?|[^\s<>\\])*>|(?:\\[()]?|\([^\s\x00-\x1f\\]*\)|[^\s\x00-\x1f()\\])*?)"
let LINK_TITLE = r""""(?:\\"?|[^"\\])*"|'(?:\\'?|[^'\\])*'|\((?:\\\)?|[^)\\])*\)"""
let INLINE_AUTOLINK = r"<(" & LINK_SCHEME & r"[^\s\x00-\x1f<>]*|" & LINK_EMAIL & ")>"
let INLINE_LINK = r"!?\[(" & LINK_LABEL & r")\]\(" & LINK_HREF & r"(?:\s+(" & LINK_TITLE & r"))?\s*\)"
let INLINE_REFLINK = r"!?\[(" & LINK_LABEL & r")\]\[(?!\s*\])((?:\\[\[\]]?|[^\[\]\\])+)\]"
let INLINE_NOLINK = r"!?\[(?!\s*\])((?:\[[^\[\]]*\]|\\[\[\]]|[^\[\]])*)\](?:\[\])?"

let BULLET = r"(?:[*+-]|\d+\.)"
let HR = r" {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*(?:\n+|$)"
let DEF = r" {0,3}\[(" & LINK_LABEL & r")\]: *\n? *<?([^\s>]+)>?(?:(?: +\n? *| *\n *)(" & LINK_TITLE & r"))? *(?:\n+|$)"
let LIST = (
  r"( *)(" & BULLET & r") [\s\S]+?(?=\n+" &
  HR.replace(r"\1", r"\4") &
  r"|\n+(?=" &
  DEF &
  r")|\n{2,}(?! )(?!\2" &
  BULLET &
  r" )\n*|\s*$)"
)

let TAG = (
  "address|article|aside|base|basefont|blockquote|body|caption" &
  "|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption" &
  "|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe" &
  "|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option" &
  "|p|param|section|source|summary|table|tbody|td|tfoot|th|thead|title|tr" &
  "track|ul"
)
let RE_HEADING = r"^ *(#{1,6}) *([^\n]+?) *(?:#+ *)?(?:\n+|$)"
let RE_LHEADING = r"^([^\n]+)\n *(=|-){2,} *(?:\n+|$)"
let RE_PARAGRAPH = (
  r"[^\n]+(?:\n(?!" &
  HR & r"|" & RE_HEADING & r"|" & RE_LHEADING & "|" &
  r" {0,3}>" & "|" & r"<\/?(?:" & TAG & r")(?: +|\n|\/?>)|<(?:script|pre|style|!--))[^\n]+)*"
)

let RE_ATX_HEADING = r" {0,3}(#{1,6})( +)?(?(2)([^\n]*?))( +)?(?(4)#*) *(?:\n+|$)"

let RE_BLOCKQUOTE = (
  r"(( *>[^\n]*(\n[^\n]+)*\n*)+)(?=" &
  HR.replace(r"\1", r"\4") & "|" &
  r"\n{2,}|$" &
  r")"
)

var blockRules = @{
  MarkdownTokenType.ATXHeading: re("^" & RE_ATX_HEADING),
  MarkdownTokenType.SetextHeading: re"^(((?:(?:[^\n]+)\n)+) {0,3}(=|-)+ *(?:\n+|$))",
  MarkdownTokenType.ThematicBreak: re"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*(?:\n+|$)",
  MarkdownTokenType.IndentedBlockCode: re"^(( {4}[^\n]+\n*)+)",
  MarkdownTokenType.FencingBlockCode: re"^( *(`{3,}|~{3}) *([^`\s]+)? *\n([\s\S]+?)\s*\2 *(\n+|$))",
  MarkdownTokenType.BlockQuote: re("^" & RE_BLOCKQUOTE),
  MarkdownTokenType.Paragraph: re(
    r"^(((?:[^\n]+\n?" &
    r"(?!" &
    r" {0,3}[-*_](?: *[-*_]){2,} *(?:\n+|$)|" & # ThematicBreak
    r"( *>[^\n]+(\n[^\n]+)*\n*)+|" & # blockquote
    r" {0,3}(?:#{1,6}) +(?:[^\n]+?) *#* *(?:\n+|$)|" & # atx heading
    LIST & # list
    r"))+)\n*)"
  ),
  MarkdownTokenType.ListBlock: re(
    r"^(" & LIST & ")"
  ),
  MarkdownTokenType.ListItem: re(
    r"^(( *)(?:[*+-]|\d+\.) [^\n]*" &
    r"(?:\n(?!\2(?:[*+-]|\d+\.) )[^\n]*)*)",
    {RegexFlag.reMultiLine}
  ),
  MarkdownTokenType.DefineLink: re"^( {0,3}\[([^^\]]+)\]: *\n? *<?([^\s>]+)>?(?:(?: *\n? +)[\""'(]([^\n]+)[\""')])? *(?:\n+|$))",
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
  MarkdownTokenType.AutoLink: re("^(" & INLINE_AUTOLINK & ")"),
  MarkdownTokenType.InlineText: re"^([\p{P}]+(?=[*_]+(?!_|\s|\p{Z}|\xa0))|[\s\S]+?(?=[\\<!\[`~]|[\s\p{P}]*\*+(?!_|\s|\p{Z}|\xa0)|[\s\p{P}]+_+(?!_|\s|\p{Z}|\xa0)|https?://| {2,}\n|$))",
  MarkdownTokenType.InlineEscape: re(
    r"^\\([\\`*{}\[\]()#+\-.!_<>~|""$%&',/:;=?@^])"
  ),
  MarkdownTokenType.InlineHTML: re(
    "^(" & HTML_TAG & ")", {RegexFlag.reIgnoreCase}
  ),
  MarkdownTokenType.InlineLink: re(
    "^(" & INLINE_LINK & ")"
  ),
  MarkdownTokenType.InlineRefLink: re(
    "^(" & INLINE_REFLINK & ")"
  ),
  MarkdownTokenType.InlineNoLink: re("^(" & INLINE_NOLINK & ")"),
  MarkdownTokenType.InlineURL: re(
    r"""^((https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9]\.[^\s]{2,}))"""
  ),
  MarkdownTokenType.InlineDoubleEmphasis: re(
    r"^(_{2}([\w\d][\s\S]*?(?<![\\\s]))_{2}(?!_)(?>=\s*|$)" &
    r"|\*{2}([\w\d][\s\S]*?(?<![\\\s]))\*{2}(?!\*))"
  ),
  MarkdownTokenType.InlineEmphasis: re(
    r"^(_((?!_|\s|\p{Z}|\xa0)[\s\S]*?(?<![\\\s_]))_(?!_)(?>=\s*|$)" &
    r"|\*((?!_|\s|\p{Z}|\xa0)[\s\S]*?(?<![\\\s*]))\*(?!\*|\p{P}))"
  ),
  MarkdownTokenType.InlineCode: re"^((`+)\s*([\s\S]*?[^`])\s*\2(?!`))",
  MarkdownTokenType.InlineBreak: re"^((?: {2,}\n|\\\n)(?!\s*$))",
  MarkdownTokenType.InlineStrikethrough: re"^(~~(?=\S)([\s\S]*?\S)~~)",
  MarkdownTokenType.InlineFootnote: re"^(\[\^([^\]]+)\])",
}.newTable



let blockParsingOrder = @[
  MarkdownTokenType.DefineLink,
  MarkdownTokenType.DefineFootnote,
  MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  MarkdownTokenType.BlockQuote,
  MarkdownTokenType.ThematicBreak,
  MarkdownTokenType.ATXHeading,
  MarkdownTokenType.ListBlock,
  MarkdownTokenType.SetextHeading,
  
  MarkdownTokenType.HTMLBlock,
  MarkdownTokenType.HTMLTable,
  MarkdownTokenType.Paragraph,
  MarkdownTokenType.Newline,
]

let listParsingOrder = @[
  MarkdownTokenType.Newline,
  # MarkdownTokenType.IndentedBlockCode,
  MarkdownTokenType.FencingBlockCode,
  # MarkdownTokenType.ATXHeading,
  # MarkdownTokenType.ThematicBreak,
  # MarkdownTokenType.BlockQuote,
  MarkdownTokenType.ListBlock,
  MarkdownTokenType.HTMLBlock,
  MarkdownTokenType.InlineEscape,
  MarkdownTokenType.InlineHTML,
  MarkdownTokenType.InlineURL,
  MarkdownTokenType.InlineLink,
  MarkdownTokenType.InlineFootnote,
  MarkdownTokenType.InlineRefLink,
  MarkdownTokenType.InlineNoLink,
  MarkdownTokenType.InlineDoubleEmphasis,
  MarkdownTokenType.InlineEmphasis,
  MarkdownTokenType.InlineCode,
  MarkdownTokenType.InlineBreak,
  MarkdownTokenType.InlineStrikethrough,
  MarkdownTokenType.AutoLink,
  MarkdownTokenType.InlineText,
]

let inlineParsingOrder = @[
  MarkdownTokenType.InlineEscape,
  MarkdownTokenType.InlineHTML,
  MarkdownTokenType.InlineURL,
  MarkdownTokenType.InlineLink,
  MarkdownTokenType.InlineFootnote,
  MarkdownTokenType.InlineRefLink,
  MarkdownTokenType.InlineNoLink,
  MarkdownTokenType.InlineDoubleEmphasis,
  MarkdownTokenType.InlineEmphasis,
  MarkdownTokenType.InlineCode,
  MarkdownTokenType.InlineBreak,
  MarkdownTokenType.InlineStrikethrough,
  MarkdownTokenType.AutoLink,
  MarkdownTokenType.InlineText,
]

let inlineLinkParsingOrder = @[
  MarkdownTokenType.InlineEscape,
  MarkdownTokenType.InlineDoubleEmphasis,
  MarkdownTokenType.InlineEmphasis,
  MarkdownTokenType.InlineCode,
  MarkdownTokenType.InlineBreak,
  MarkdownTokenType.InlineStrikethrough,
  MarkdownTokenType.InlineText,
]

proc findToken*(doc: string, start: var int, ruleType: MarkdownTokenType): MarkdownTokenRef;
proc parseInlines*(ctx: MarkdownContext, doc: string): seq[MarkdownTokenRef];
proc renderToken*(ctx: MarkdownContext, token: MarkdownTokenRef): string;

proc preprocessing*(doc: string): string =
  ## Pre-processing the text.
  result = doc.replace(re"\r\n|\r", "\n")
  result = result.replace(re"^\t", "    ")
  result = result.replace(re"^ {1,3}\t", "    ")
  result = result.replace("\u2424", " ")
  result = result.replace("\u0000", "\uFFFD")
  result = result.replace("&#0;", "&#XFFFD;")
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
  result = doc.escapeAmpersandChar.escapeTag

const IGNORED_HTML_ENTITY = ["&lt;", "&gt;", "&amp;"]

proc escapeHTMLEntity*(doc: string): string =
  var entities = doc.findAll(re"&([^;]+);")
  result = doc
  for entity in entities:
    if not IGNORED_HTML_ENTITY.contains(entity):
      var utf8Char = entity[1 .. entity.len-2].entityToUtf8
      if utf8Char != "":
        result = result.replace(re(entity), utf8Char)
      else:
        result = result.replace(re(entity), entity.escapeAmpersandChar)

proc escapeLinkUrl*(url: string): string =
  encodeUrl(url.escapeHTMLEntity, usePlus=false).replace("%40", "@"
    ).replace("%3A", ":"
    ).replace("%2B", "+"
    ).replace("%3F", "?"
    ).replace("%3D", "="
    ).replace("%26", "&"
    ).replace("%28", "("
    ).replace("%29", ")"
    ).replace("%25", "%"
    ).replace("%23", "#"
    ).replace("%2A", "*"
    ).replace("%2C", ","
    ).replace("%2F", "/")

proc escapeBackslash*(doc: string): string =
  doc.replacef(re"\\([\\`*{}\[\]()#+\-.!_<>~|""$%&',/:;=?@^])", "$1")

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
  result = MarkdownTokenRef(type: MarkdownTokenType.Newline, newlineVal: matches[0])

proc genATXHeading(matches: openArray[string], ): MarkdownTokenRef =
  var val: Heading
  val.level = matches[0].len
  if matches[2] =~ re"#+": # ATX headings can be empty. Ignore closing sequence if captured.
    val.inlines = @[]
  else:
    val.inlines = toSeq(parseTokens(matches[2], inlineParsingOrder))
  result = MarkdownTokenRef(type: MarkdownTokenType.ATXHeading, atxHeadingVal: val) 

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
  val.lang = matches[2]
  val.code = matches[3]
  result = MarkdownTokenRef(type: MarkdownTokenType.FencingBlockCode, fencingBlockCodeVal: val)

proc genParagraph(matches: openArray[string]): MarkdownTokenRef =
  var doc = matches[0].strip(chars={'\n', ' '}).replace(re"\n *", "\n")
  var tokens: seq[MarkdownTokenRef] = @[]
  var val = Paragraph(inlines: tokens, doc: doc)
  result = MarkdownTokenRef(type: MarkdownTokenType.Paragraph, paragraphVal: val)

proc genText(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.Text, textVal: matches[0])

proc genDefineLink(matches: openArray[string]): MarkdownTokenRef =
  if matches[1].match(re"\s+"):
    return genParagraph(@[matches[0]])

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
    if index > aligns.len - 1:
      head.cells[index].align = ""
    else:
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
  link.url = matches[1]
  link.text = matches[1]
  link.isEmail = matches[1].match(re(LINK_EMAIL))
  link.isImage = false
  result = MarkdownTokenRef(type: MarkdownTokenType.AutoLink, autoLinkVal: link)

proc genInlineText(matches: openArray[string]): MarkdownTokenRef =
  var text = matches[0].replace(re" *\n", "\n")
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: text)

proc genInlineEscape(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineEscape, inlineEscapeVal: matches[0])

proc isSquareBalanced(text: string): bool =
  var stack: seq[char]
  var isEscaped = false
  for ch in text:
    if isEscaped:
      continue
    elif ch == '[':
      stack.add(ch)
    elif ch == ']':
      if stack.len > 0:
        discard stack.pop
      else:
        return false
    elif ch == '\\':
      isEscaped = true
    else:
      continue
  result = stack.len == 0

proc genInlineLink(matches: openArray[string]): MarkdownTokenRef =
  #echo(matches)
  # if matches[3].contains(re"\n"):
  #   return MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: matches[0])
  # if matches[2] != "<" and matches[3].contains(re"\s"):
  #   return MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: matches[0])
  # if not matches[1].isSquareBalanced:
  #   return MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: matches[0])
  var link: Link
  link.isEmail = false
  link.isImage = matches[0][0] == '!'
  link.text = matches[1]
  link.url = matches[2]
  link.title = matches[3]
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineLink, inlineLinkVal: link)

proc genInlineHTML(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineHTML, inlineHTMLVal: matches[0])

proc genInlineRefLink(matches: openArray[string]): MarkdownTokenRef =
  var link: RefLink
  link.text = matches[1]
  if matches[2] == "":
    link.id = link.text
  else:
    link.id = matches[2]
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
  result = MarkdownTokenRef(
    type: MarkdownTokenType.InlineDoubleEmphasis,
    inlineDoubleEmphasisVal: DoubleEmphasis(inlines: @[
      MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: text)
    ])
  )

proc genInlineEmphasis(matches: openArray[string]): MarkdownTokenRef =
  if matches[2].startsWith("\u00a0") or matches[2].endswith("\u00a0"): # unicode whitespace. PCRE seems not support \u in regex.
    return MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: matches[0])
  var text: string
  if matches[0][0] == '_':
    text = matches[1]
  else:
    text = matches[2]
    result = MarkdownTokenRef(
      type: MarkdownTokenType.InlineEmphasis,
      inlineEmphasisVal: Emphasis(inlines: @[
        MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: text)
      ])
    )

proc genInlineCode(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineCode, inlineCodeVal: matches[2])

proc genInlineBreak(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineBreak, inlineBreakVal: "")

proc genInlineStrikethrough(matches: openArray[string]): MarkdownTokenRef =
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineStrikethrough, inlineStrikethroughVal: matches[1])

proc genInlineFootnote(matches: openArray[string]): MarkdownTokenRef =
  let footnote = RefFootnote(anchor: matches[1])
  result = MarkdownTokenRef(type: MarkdownTokenType.InlineFootnote, inlineFootnoteVal: footnote)


const ENTITY = r"&(?:#x[a-f0-9]{1,6}|#[0-9]{1,7}|[a-z][a-z0-9]{1,31});"

proc parseNewline*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] = @[]

proc parseBackslash*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  var pos: int = start
  var token: MarkdownTokenRef

  token = findToken(doc, pos, MarkdownTokenType.InlineBreak)
  if token != nil:
    size = pos - start
    return @[token]

  token = findToken(doc, pos, MarkdownTokenType.InlineEscape)
  if token != nil:
    size = pos - start
    return @[token]

  size = -1
  result = @[]

proc parseBacktick*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  var pos = start
  let token = findToken(doc, pos, MarkdownTokenType.InlineCode)
  if token == nil:
    size = -1
    result = @[]
  else:
    size = pos - start
    result = @[token]

proc scanInlineDelimeters*(doc: string, start: int, delimeter: var Delimeter) =
  var charBefore = '\n'
  var charAfter = '\n'
  let charCurrent = doc[start]

  # get the number of delimeters.
  for ch in doc[start .. doc.len - 1]:
    if ch == charCurrent:
      delimeter.num += 1
      delimeter.originalNum += 1
    else:
      break

  # get the character before the starting character
  if start > 0:
    charBefore = doc[start - 1]

  # get the character after the delimeter runs
  if start + delimeter.num + 1 < doc.len:
    charAfter = doc[start + delimeter.num]

  let isCharAfterWhitespace = fmt"{charAfter}".match(re"^\s") or charAfter == '\u00a0'
  let isCharAfterPunctuation = fmt"{charAfter}".match(re"^\p{P}")
  let isCharBeforeWhitespace = fmt"{charBefore}".match(re"^\s") or charBefore == '\u00a0'
  let isCharBeforePunctuation = fmt"{charBefore}".match(re"^\p{P}")

  let isLeftFlanking = (
    (not isCharAfterWhitespace) and (
      (not isCharAfterPunctuation) or isCharBeforeWhitespace or isCharBeforePunctuation
    )
  )

  let isRightFlanking = (
    (not isCharBeforeWhitespace) and (
      (not isCharBeforePunctuation) or isCharAfterWhitespace or isCharAfterPunctuation
    )
  )

  case charCurrent
  of '_':
    delimeter.canOpen = isLeftFlanking and ((not isRightFlanking) or isCharBeforePunctuation)
    delimeter.canClose = isRightFlanking and ((not isLeftFlanking) or isCharAfterPunctuation)
  else:
    delimeter.canOpen = isLeftFlanking
    delimeter.canClose = isRightFlanking

  #echo(fmt"{delimeter.canOpen} {delimeter.canClose}")

proc parseDelimeter*(doc: string, start: int, size: var int, delimeterStack: var DoublyLinkedList[Delimeter]): seq[MarkdownTokenRef] =
  ## add a placeholder for delimeter and append a delimeter to the stack.
  var delimeter = Delimeter(
    token: nil,
    kind: fmt"{doc[start]}",
    num: 0,
    originalNum: 0,
    isActive: true,
    canOpen: false,
    canClose: false,
  )

  scanInlineDelimeters(doc, start, delimeter)

  if delimeter.num == 0:
    return @[]

  size = delimeter.num

  var inlineText = MarkdownTokenRef(
    type: MarkdownTokenType.InlineText,
    inlineTextVal: doc[start .. start + size - 1]
  )

  result = @[inlineText]
  delimeter.token = inlineText
  delimeterStack.append(delimeter)

proc removeDelimeter*(delimeter: var DoublyLinkedNode[Delimeter]) =
  if delimeter.prev != nil:
    delimeter.prev.next = delimeter.next
  if delimeter.next != nil:
    delimeter.next.prev = delimeter.prev
  delimeter = delimeter.next

proc processEmphasis*(tokens: var seq[MarkdownTokenRef], delimeterStack: var DoublyLinkedList[Delimeter]) =
  var opener: DoublyLinkedNode[Delimeter] = nil
  var closer: DoublyLinkedNode[Delimeter] = nil
  var oldCloser: DoublyLinkedNode[Delimeter] = nil
  var openerFound = false
  var oddMatch = false
  var useDelims = 0
  var underscoreOpenerBottom: DoublyLinkedNode[Delimeter] = nil
  var asteriskOpenerBottom: DoublyLinkedNode[Delimeter] = nil

  # find first closer above stack_bottom
  closer = delimeterStack.head

  # move forward, looking for closers, and handling each
  while closer != nil:
    # find the first closing delimeter.
    if not closer.value.canClose:
      closer = closer.next
      continue
    # found emphasis closer. now look back for first matching opener.
    opener = closer.prev
    openerFound = false
    while opener != nil and (
      (opener.value.kind == "*" and opener != asteriskOpenerBottom
      ) or (opener.value.kind == "_" and opener != underscoreOpenerBottom)
    ):
      # oddMatch: **abc*d*abc***
      # the second * between `abc` and `d` makes oddMatch to true
      oddMatch = (
        closer.value.canOpen or opener.value.canClose
      ) and (opener.value.originalNum + closer.value.originalNum) mod 3 == 0

      # found opener when opener has same kind with closer and iff it's not odd match
      if opener.value.kind == closer.value.kind and opener.value.canOpen and not oddMatch:
        openerFound = true
        break
      opener = opener.prev

    oldCloser = closer

    # if one is found.
    if not openerFound:
      closer = closer.next
    else:
      # calculate actual number of delimiters used from closer
      if closer.value.num >= 2 and opener.value.num >= 2:
        useDelims = 2
      else:
        useDelims = 1

      var openerInlineText = opener.value.token
      var closerInlineText = closer.value.token

      # remove used delimiters from stack elts and inlines
      opener.value.num -= useDelims
      closer.value.num -= useDelims
      openerInlineText.inlineTextVal = openerInlineText.inlineTextVal[0 .. ^(useDelims+1)]
      closerInlineText.inlineTextVal = closerInlineText.inlineTextVal[0 .. ^(useDelims+1)]

      # build contents for new emph element
      var isEmphasized = false
      var startIndex = 0
      var endIndex = 0
      var inlines: seq[MarkdownTokenRef] = @[]
      for index, token in tokens:
        if token == opener.value.token:
          isEmphasized = true
          startIndex = index
        elif token == closer.value.token:
          isEmphasized = false
          endIndex = index
        elif isEmphasized:
          inlines.add(token)
      tokens.delete(startIndex + 1, endIndex - 1)

      # add emph element to tokens
      var emph: MarkdownTokenRef
      if useDelims == 2:
        emph = MarkdownTokenRef(type: MarkdownTokenType.InlineDoubleEmphasis, inlineDoubleEmphasisVal: DoubleEmphasis(inlines: inlines))
      else:
        emph = MarkdownTokenRef(type: MarkdownTokenType.InlineEmphasis, inlineEmphasisVal: Emphasis(inlines: inlines))
      tokens.insert(emph, startIndex + 1)

      # remove elts between opener and closer in delimiters stack
      if opener.next != closer:
        opener.next = closer
        closer.prev = opener

      # remove closer if no text left
      if closer.value.num == 0:
        tokens.delete(startIndex + 2) # the closer token
        var tmp = closer.next
        removeDelimeter(closer)
        closer = tmp

      # remove opener if no text left
      if opener.value.num == 0:
        tokens.delete(startIndex)
        removeDelimeter(opener)

    # if none is found.
    if not openerFound and not oddMatch:
      # Set openers_bottom to the element before current_position. 
      # (We know that there are no openers for this kind of closer up to and including this point,
      # so this puts a lower bound on future searches.)
      if oldCloser.value.kind == "*":
        asteriskOpenerBottom = oldCloser.prev
      else:
        underscoreOpenerBottom = oldCloser.prev
      # If the closer at current_position is not a potential opener,
      # remove it from the delimiter stack (since we know it can’t be a closer either).
      if not oldCloser.value.canOpen:
        removeDelimeter(oldCloser)

  # after done, remove all delimiters
  while delimeterStack.head != nil:
    removeDelimeter(delimeterStack.head)

proc parseQuote*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] = @[]

proc parseBang*(doc: string, start: int, size: var int, delimeterStack: var DoublyLinkedList[Delimeter]): seq[MarkdownTokenRef] =
  var pos: int = start
  var token: MarkdownTokenRef

  token = findToken(doc, pos, MarkdownTokenType.InlineLink)
  if token != nil:
    size = pos - start
    return @[token]

  size = -1
  result = @[]

proc parseOpenBracket*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  var pos: int = start
  var token: MarkdownTokenRef

  token = findToken(doc, pos, MarkdownTokenType.InlineRefLink)
  if token != nil:
    size = pos - start
    return @[token]

  token = findToken(doc, pos, MarkdownTokenType.InlineLink)
  if token != nil:
    size = pos - start
    return @[token]

  token = findToken(doc, pos, MarkdownTokenType.InlineNoLink)
  if token != nil:
    size = pos - start
    return @[token]

  size = -1
  result = @[]

proc parseHTMLEntity*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  let regex = re(r"^(" & ENTITY & ")", {RegexFlag.reIgnoreCase})
  var matches: array[1, string]
  size = doc[start .. doc.len - 1].matchLen(regex, matches)

  var entity: string

  if size == -1:
    return @[]

  if matches[0] == "&#0;":
    entity = "\uFFFD"
  else:
    entity = escapeHTMLEntity(matches[0])

  result = @[MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: entity)]

proc parseAutolink*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  var pos: int = start
  var token: MarkdownTokenRef

  token = findToken(doc, pos, MarkdownTokenType.Autolink)
  if token != nil:
    size = pos - start
    return @[token]

  size = -1
  result = @[]

proc parseHTMLTag*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  var pos: int = start
  var token: MarkdownTokenRef

  token = findToken(doc, pos, MarkdownTokenType.InlineHTML)
  if token != nil:
    size = pos - start
    return @[token]

  size = -1
  result = @[]

proc parseString*(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  var pos: int = start
  var token: MarkdownTokenRef

  token = findToken(doc, pos, MarkdownTokenType.InlineURL)
  if token != nil:
    size = pos - start
    return @[token]

  token = findToken(doc, pos, MarkdownTokenType.InlineStrikethrough)
  if token != nil:
    size = pos - start
    return @[token]

  size = -1
  result = @[]

proc parseLessThan(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  result = parseHTMLTag(doc, start, size)

  if result.len != 0:
    return result

  result = parseAutolink(doc, start, size)

proc parseHardLineBreak(doc: string, start: int, size: var int): seq[MarkdownTokenRef] =
  size = doc[start .. doc.len - 1].matchLen(re"^ {2,}\n *")
  if size != -1:
    return @[MarkdownTokenRef(type: MarkdownTokenType.InlineBreak, inlineBreakVal: "")]

  size = doc[start .. doc.len - 1].matchLen(re" \n *")
  if size != -1:
    return @[MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: "\n")]

  result = @[]
  

proc parseInlines*(ctx: MarkdownContext, doc: string): seq[MarkdownTokenRef] =
  var pos = 0
  var delimeterStack: DoublyLinkedList[Delimeter]

  for index, ch in doc:
    if index < pos:
      continue

    var size = -1
    var tokens: seq[MarkdownTokenRef] = @[]

    case ch
    of '\n': tokens = parseNewline(doc, index, size)
    of '\\': tokens = parseBackslash(doc, index, size)
    of '`': tokens = parseBacktick(doc, index, size)
    of '*': tokens = parseDelimeter(doc, index, size, delimeterStack)
    of '_': tokens = parseDelimeter(doc, index, size, delimeterStack)
    of '\'': tokens = parseQuote(doc, index, size)
    of '"': tokens = parseQuote(doc, index, size)
    of '[': tokens = parseOpenBracket(doc, index, size)
    of '!': tokens = parseBang(doc, index, size, delimeterStack)
    of '&': tokens = parseHTMLEntity(doc, index, size)
    of '<': tokens = parseLessThan(doc, index, size)
    of ' ': tokens = parseHardLineBreak(doc, index, size)
    else: tokens = parseString(doc, index, size)

    if size == -1:
      tokens.add(MarkdownTokenRef(type: MarkdownTokenType.InlineText, inlineTextVal: fmt"{ch}"))
      pos = index + 1
    else:
      pos += size

    result.insert(tokens, result.len)

  result.processEmphasis(delimeterStack)

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
  of MarkdownTokenType.ATXHeading: result = genATXHeading(matches)
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
  var lang: string
  if fence.lang == "":
    lang = ""
  else:
    lang = fmt(" class=\"language-{escapeHTMLEntity(escapeBackslash(fence.lang))}\"")
  result = fmt("""<pre><code{lang}>{escapeCode(fence.code)}
</code></pre>""")

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
  result = "<blockquote>\n"
  for token in blockQuote.blocks:
    result &= renderToken(ctx, token)
    result &= "\n"
  result &= "</blockquote>"

proc renderListItem(ctx: MarkdownContext, listItem: ListItem): string =
  for el in listItem.blocks:
    result &= renderToken(ctx, el)
  result = fmt("<li>{result}</li>\n")

proc renderListBlock(ctx: MarkdownContext, listBlock: ListBlock): string =
  result = ""
  for el in listBlock.blocks:
    result &= renderListItem(ctx, el.listItemVal)
  if listBlock.ordered:
    result = fmt("<ol>\n{result}</ol>")
  else:
    result = fmt("<ul>\n{result}</ul>")

proc escapeInvalidHTMLTag(doc: string): string =
  doc.replacef(
    re(r"<(title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)>",
      {RegexFlag.reIgnoreCase}),
    "&lt;$1>")

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
    result = fmt("<{tag} style=\"text-align: {cell.align}\">")
  else:
    result = fmt("<{tag}>")
  for token in cell.dom:
    result &= renderToken(ctx, token)
  result &= fmt("</{tag}>\n")

proc renderHTMLTable*(ctx: MarkdownContext, table: HTMLTable): string =
  result &= "<table>\n"
  result &= "<thead>\n"
  result &= "<tr>\n"
  for headCell in table.head.cells:
    result &= renderHTMLTableCell(ctx, headCell, tag="th")
  result &= "</tr>\n"
  result &= "</thead>\n"
  if table.body.len > 0:
    result &= "<tbody>\n"
    for row in table.body:
      result &= "<tr>\n"
      for cell in row.cells:
        result &= renderHTMLTableCell(ctx, cell, tag="td")
      result &= "</tr>"
    result &= "</tbody>"
  result &= "</table>"

proc renderInlineEscape(ctx: MarkdownContext, inlineEscape: string): string =
  result = inlineEscape.escapeAmpersandSeq.escapeTag.escapeQuote

proc renderInlineText(ctx: MarkdownContext, inlineText: string): string =
  if ctx.config.escape:
    result = renderInlineEscape(ctx, escapeHTMLEntity(inlineText))
  else:
    result = escapeHTMLEntity(inlineText)

proc renderLinkTitle(text: string): string =
  var title: string
  if text != "":
    fmt(" title=\"{text.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote}\"")
  else:
    ""

proc renderImageAlt(text: string): string =
  var alt = text.escapeBackslash.escapeQuote.replace(re"\*", "")
  fmt(" alt=\"{alt}\"")

proc renderLinkText(ctx: MarkdownContext, text: string): string =
  for token in parseTokens(text, inlineParsingOrder):
    result &= renderToken(ctx, token)

proc renderAutoLink(ctx: MarkdownContext, link: Link): string =
  if link.isEmail and link.url.find(re(r"^mailto:", {RegexFlag.reIgnoreCase})) != -1:
    return fmt"""<a href="{link.url}">{link.text}</a>"""

  if link.isEmail and link.url.find(re"\\") != -1:
    return fmt"""&lt;{link.url.escapeBackslash}&gt;"""

  if link.isEmail:
    return fmt"""<a href="mailto:{link.url}">{link.text}</a>"""

  var text = link.url.escapeAmpersandSeq
  var url = link.url.escapeLinkUrl.escapeAmpersandChar

  if link.url.contains(" "):
    return fmt"""&lt;{url}&gt;"""

  if link.url.matchLen(re"^[^:]+:") == -1:
    return fmt"""<a href="http://{url}">{text}</a>"""

  result = fmt"""<a href="{url}">{text}</a>"""

proc renderInlineLink(ctx: MarkdownContext, link: Link): string =
  var refId = link.text.toLower.replace(re"\s+", " ")
  if ctx.links.contains(refId):
    var definedLink = ctx.links[refId]
    let url = escapeLinkUrl(escapeBackslash(definedLink.url))
    if link.isImage:
      return fmt"""<img src="{url}"{renderImageAlt(link.text)}{renderLinkTitle(definedLink.title)} />"""
    else:
      return fmt"""<a href="{url}"{renderLinkTitle(definedLink.title)}>{renderLinkText(ctx, link.text)}</a>"""
  let url = escapeLinkUrl(escapeBackslash(link.url))
  if link.isImage:
    result = fmt"""<img src="{url}"{renderImageAlt(link.text)}{renderLinkTitle(link.title)} />"""
  else:
    result = fmt"""<a href="{url}"{renderLinkTitle(link.title)}>{renderLinkText(ctx, link.text)}</a>"""

proc renderInlineRefLink(ctx: MarkdownContext, link: RefLink): string =
  var id = link.id.toLower.replace(re"\s+", " ")
  if ctx.links.hasKey(id):
    let definedLink = ctx.links[id]
    let url = escapeLinkUrl(escapeBackslash(definedLink.url))
    if link.isImage:
      result = fmt"""<img src="{url}"{renderImageAlt(link.text)}{renderLinkTitle(definedLink.title)} />"""
    else:
      result = fmt"""<a href="{url}"{renderLinkTitle(definedLink.title)}>{renderLinkText(ctx, link.text)}</a>"""
  else:
    if link.id != "" and link.text != "" and link.id != link.text:
      result = fmt"[{link.text}][{renderLinkText(ctx, link.id)}]"
    elif link.isImage:
      result = fmt"![{link.id}]"
    else:
      result = fmt"[{link.id}]"

proc renderInlineURL(ctx: MarkdownContext, url: string): string =
  if url.matchLen(re"^[^:]+:") == -1:
    return fmt"""<a href="http://{escapeBackslash(url)}">{url}</a>"""

  result = fmt"""<a href="{escapeBackslash(url)}">{url}</a>"""

proc renderInlineHTML(ctx: MarkdownContext, html: string): string =
  result = html.escapeInvalidHTMLTag

proc renderInlineDoubleEmphasis(ctx: MarkdownContext, emph: DoubleEmphasis): string =
  var em = ""
  for token in emph.inlines:
    em &= renderToken(ctx, token)
  result = fmt"""<strong>{em}</strong>"""

proc renderInlineEmphasis(ctx: MarkdownContext, emph: Emphasis): string =
  var em = ""
  for token in emph.inlines:
    em &= renderToken(ctx, token)
  result = fmt"""<em>{em}</em>"""

proc renderInlineCode(ctx: MarkdownContext, code: string): string =
  let formattedCode = code.strip.escapeAmpersandChar.escapeTag.escapeQuote.replace(re"\s+", " ")
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
  of MarkdownTokenType.ATXHeading: result = renderHeading(ctx, token.atxHeadingVal)
  of MarkdownTokenType.SetextHeading: result = renderHeading(ctx, token.setextHeadingVal)
  of MarkdownTokenType.ThematicBreak: result = renderThematicBreak()
  of MarkdownTokenType.Text: result = renderText(ctx, token.textVal)
  of MarkdownTokenType.IndentedBlockCode: result = renderIndentedBlockCode(token.codeVal)
  of MarkdownTokenType.FencingBlockCode: result = renderFencingBlockCode(token.fencingBlockCodeVal)
  of MarkdownTokenType.Paragraph:
    for inlineToken in parseInlines(ctx, token.paragraphVal.doc):
      token.paragraphVal.inlines.add(inlineToken)
    result = renderParagraph(ctx, token.paragraphVal)
  of MarkdownTokenType.BlockQuote: result = renderBlockQuote(ctx, token.blockQuoteVal)
  of MarkdownTokenType.ListBlock: result = renderListBlock(ctx, token.listBlockVal)
  of MarkdownTokenType.ListItem: result = renderListItem(ctx, token.listItemVal)
  of MarkdownTokenType.HTMLBlock: result = renderHTMLBlock(ctx, token.htmlBlockVal)
  of MarkdownTokenType.HTMLTable: result = renderHTMLTable(ctx, token.htmlTableVal)
  of MarkdownTokenType.InlineText: result = renderInlineText(ctx, token.inlineTextVal)
  of MarkdownTokenType.InlineEscape: result = renderInlineEscape(ctx, token.inlineEscapeVal)
  of MarkdownTokenType.AutoLink: result = renderAutoLink(ctx, token.autoLinkVal)
  of MarkdownTokenType.InlineHTML: result = renderInlineHTML(ctx, token.inlineHTMLVal)
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

proc buildContext*(tokens: seq[MarkdownTokenRef], config: MarkdownConfig): MarkdownContext =
  # add building context
  result = MarkdownContext(
    links: initTable[string, Link](),
    footnotes: initTable[string, string](),
    config: config
  )
  for token in tokens:
    case token.type
    of MarkdownTokenType.DefineLink:
      var id = token.defineLinkVal.text.toLower.replace(re"\s+", " ")
      if not result.links.contains(id):
        result.links[id] = Link(
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
    var html = renderToken(ctx, token)
    if html != "":
      result &= html
      result &= "\n"

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
## # nim-markdown
##
## Most markdown parsers parse markdown documents in two steps, so does nim-markdown.
## The two-step consists of blocks parsing and inline parsing.
##
## * **Block Parsing**: One or more lines belongs to blocks, such as `<p>`, `<h1>`, etc.
## * **Inline Parsing**: Textual contents within the lines belongs to inlines, such as `<a>`, `<em>`, `<strong>`, etc.
##
## When parsing block elements, nim-markdown follows this algorithm:
##
## * Step 1. Track current position `pos` in the document.
## * Step 2. If the document since pos matches one of our parsers, then apply it.
## * Step 3. After parsing, a new token is appended to the parent token, and then we advance pos.
## * Step 4. Go back to Step 1 until the end of file.
##
## ```
## # Hello World\nWelcome to **nim-markdown**.\nLet's parse it.
## ^              ^                                            ^
## 0              14                                           EOF
##
## ^Document, pos=0
##
## ^Heading(level=1, doc="Hello World"), pos=14.
##
##                ^Paragraph(doc="Wel..."), pos=EOF.
##                                                             ^EOF, exit parsing.
## ```
##
## After the block parsing step, a tree with only Block Tokens is constructed.
##
## ```
## Document()
## +-Heading(level=1, doc="Hello World")
## +-Paragraph(doc="Wel...")
## ```
##
## Then, we proceed to inline parsing. It walks the tree and expands more inline elements.
## The algorithm is the same, except we apply it to every Block Token.
## Eventually, we get something like this:
##
## ```
## Document()
## +-Heading(level=1)
##   +-Text("H")
##   +-Text("e")
##   +-Text("l")
##   +-Text("l")
##   +-Text("o")
##   ...
## +-Paragraph()
##   +-Text("W")
##   +-Text("e")
##   ...
##   +-Em()
##     +-Text("n")
##     +-Text("i")
##     +-Text("m")
##     ...
##   +-Text(".")
##   ...
## ```
##
## Finally, All Token types support conversion to HTML strings with the special $ proc,
##

import re
from strformat import fmt, `&`
from uri import encodeUrl
from strutils import join, splitLines, repeat, replace,
  strip, split, multiReplace, startsWith, endsWith,
  parseInt, intToStr, splitWhitespace, contains, find
from tables import Table, initTable, mgetOrPut, contains, `[]=`, `[]`
import unicode except `strip`, `splitWhitespace`
from lists import DoublyLinkedList, DoublyLinkedNode,
  initDoublyLinkedList, newDoublyLinkedNode, prepend, append,
  items, mitems, nodes, remove
from htmlgen import nil, p, br, em, strong, a, img, code, del, blockquote,
  li, ul, ol, pre, code, table, thead, tbody, th, tr, td, hr

from markdownpkg/entities import htmlEntityToUtf8

var precompiledExp {.threadvar.}: Table[string, re.Regex]



template re(data: string): Regex =
  let tmpName = data
  # We won't use mgetOrPut directly because otherwise Nim will lazily evaluate
  # the argument for mgetOrPut so that we'll have no benefit
  if tmpName in precompiledExp:
    precompiledExp[tmpName]
  else:
    precompiledExp.mgetOrPut(tmpName, re.re(tmpName))

template re(data: string, flags: set[RegexFlag]): Regex =
  let tmpName = data
  if tmpName in precompiledExp:
    precompiledExp[tmpName]
  else:
    precompiledExp.mgetOrPut(tmpName, re.re(tmpName, flags))

type
  MarkdownError* = object of ValueError## The error object for markdown parsing and rendering.
                                       ## Usually, you should not see MarkdownError raising in your application
                                       ## unless it's documented. Otherwise, please report it as an issue.
                                       ##
  Parser* = ref object of RootObj

  MarkdownConfig* = ref object ## Options for configuring parsing or rendering behavior.
    escape*: bool ## escape ``<``, ``>``, and ``&`` characters to be HTML-safe
    keepHtml*: bool ## deprecated: preserve HTML tags rather than escape it
    blockParsers*: seq[Parser]
    inlineParsers*: seq[Parser]

  ChunkKind* = enum
    BlockChunk,
    LazyChunk,
    InlineChunk

  Chunk* = ref object
    kind*: ChunkKind
    doc*: string
    pos*: int

  Token* = ref object of RootObj
    doc*: string
    pos*: int
    children*: DoublyLinkedList[Token]

  ParseResult* = ref object
    token*: Token
    pos*: int

  Document* = ref object of Token

  Block* = ref object of Token

  BlanklineParser* = ref object of Parser

  ParagraphParser* = ref object of Parser
  Paragraph* = ref object of Block
    loose*: bool
    trailing*: string

  ReferenceParser* = ref object of Parser
  Reference = ref object of Block
    text*: string
    title*: string
    url*: string

  ThematicBreakParser* = ref object of Parser
  ThematicBreak* = ref object of Block

  SetextHeadingParser* = ref object of Parser
  AtxHeadingParser* = ref object of Parser
  Heading* = ref object of Block
    level*: int

  FencedCodeParser* = ref object of Parser
  IndentedCodeParser* = ref object of Parser
  CodeBlock* = ref object of Block
    info*: string

  HtmlBlockParser* = ref object of Parser
  HtmlBlock* = ref object of Block

  BlockquoteParser* = ref object of Parser
  Blockquote* = ref object of Block
    chunks*: seq[Chunk]

  UlParser* = ref object of Parser
  Ul* = ref object of Block

  OlParser* = ref object of Parser
  Ol* = ref object of Block
    start*: int

  Li* = ref object of Block
    loose*: bool
    marker*: string
    verbatim*: string

  HtmlTableParser* = ref object of Parser
  HtmlTable* = ref object of Block
  THead* = ref object of Block
  TBody* = ref object of Block
    size*: int

  TableRow* = ref object of Block

  THeadCell* = ref object of Block
    align*: string

  TBodyCell* = ref object of Block
    align*: string

  Inline* = ref object of Token

  TextParser* = ref object of Parser
  Text* = ref object of Inline
    delimiter*: Delimiter

  CodeSpanParser* = ref object of Parser
  CodeSpan* = ref object of Inline

  SoftBreakParser* = ref object of Parser
  SoftBreak* = ref object of Inline

  HardBreakParser* = ref object of Parser
  HardBreak* = ref object of Inline

  StrikethroughParser* = ref object of Parser
  Strikethrough* = ref object of Inline

  EscapeParser* = ref object of Parser
  Escape* = ref object of Inline

  InlineHtmlParser* = ref object of Parser
  InlineHtml* = ref object of Inline

  HtmlEntityParser* = ref object of Parser
  HtmlEntity* = ref object of Inline

  LinkParser* = ref object of Parser
  Link* = ref object of Inline
    refId*: string
    text*: string ## A link contains link text (the visible text).
    url*: string ## A link contains destination (the URI that is the link destination).
    title*: string ## A link contains a optional title.

  AutoLinkParser* = ref object of Parser
  AutoLink* = ref object of Inline
    text*: string
    url*: string

  ImageParser* = ref object of Parser
  Image* = ref object of Inline
    refId*: string
    allowNested*: bool
    url*: string
    alt*: string
    title*: string

  DelimiterParser* = ref object of Parser
  Delimiter* = ref object of Inline
    token*: Text
    kind*: string
    num*: int
    originalNum*: int
    isActive*: bool
    canOpen*: bool
    canClose*: bool

  Em* = ref object of Inline

  Strong* = ref object of Inline

  State* = ref object
    references*: Table[string, Reference]
    config*: MarkdownConfig

proc parse*(state: State, token: Token);
proc render*(token: Token, sep = "\n"): string;
proc parseBlock(state: State, token: Token);
proc parseLeafBlockInlines(state: State, token: Token);
proc getLinkText*(doc: string, start: int, allowNested: bool = false): tuple[slice: Slice[int], size: int];
proc getLinkLabel*(doc: string, start: int): tuple[label: string, size: int];
proc getLinkDestination*(doc: string, start: int): tuple[slice: Slice[int], size: int];
proc getLinkTitle*(doc: string, start: int): tuple[slice: Slice[int], size: int];
proc isContinuationText*(doc: string, start: int = 0, stop: int = 0): bool;

let skipParsing = ParseResult(token: nil, pos: -1)

method parse*(this: Parser, doc: string, start: int): ParseResult {.base.} =
  ParseResult(token: Token(), pos: doc.len)

proc appendChild*(token: Token, child: Token) =
  if child of Text and token.children.tail != nil and token.children.tail.value of Text and Text(child).delimiter == Text(token.children.tail.value).delimiter:
    token.children.tail.value.doc &= child.doc
    token.children.tail.value.pos = max(token.children.tail.value.pos, child.pos)
    token.children.tail.value.children.append child.children
  else:
    token.children.append(child)

const THEMATIC_BREAK_RE = r" {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*(?:\n+|$)"

const HTML_SCRIPT_START = r" {0,3}<(script|pre|style)(?=(\s|>|$))"
const HTML_SCRIPT_END = r"</(script|pre|style)>"
const HTML_COMMENT_START = r" {0,3}<!--"
const HTML_COMMENT_END = r"-->"
const HTML_PROCESSING_INSTRUCTION_START = r" {0,3}<\?"
const HTML_PROCESSING_INSTRUCTION_END = r"\?>"
const HTML_DECLARATION_START = r" {0,3}<\![A-Z]"
const HTML_DECLARATION_END = r">"
const HTML_CDATA_START = r" {0,3}<!\[CDATA\["
const HTML_CDATA_END = r"\]\]>"
const HTML_VALID_TAGS = ["address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "meta", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "section", "source", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"]
const HTML_TAG_START = r" {0,3}</?(" & HTML_VALID_TAGS.join("|") & r")(?=(\s|/?>|$))"
const HTML_TAG_END = r"^\n?$"

const TAGNAME = r"[A-Za-z][A-Za-z0-9-]*"
const ATTRIBUTENAME = r"[a-zA-Z_:][a-zA-Z0-9:._-]*"
const UNQUOTEDVALUE = r"[^""'=<>`\x00-\x20]+"
const DOUBLEQUOTEDVALUE = """"[^"]*""""
const SINGLEQUOTEDVALUE = r"'[^']*'"
const ATTRIBUTEVALUE = "(?:" & UNQUOTEDVALUE & "|" & SINGLEQUOTEDVALUE & "|" & DOUBLEQUOTEDVALUE & ")"
const ATTRIBUTEVALUESPEC = r"(?:\s*=" & r"\s*" & ATTRIBUTEVALUE & r")"
const ATTRIBUTE = r"(?:\s+" & ATTRIBUTENAME & ATTRIBUTEVALUESPEC & r"?)"
const OPEN_TAG = r"<" & TAGNAME & ATTRIBUTE & r"*" & r"\s*/?>"
const CLOSE_TAG = r"</" & TAGNAME & r"\s*[>]"
const HTML_COMMENT = r"<!---->|<!--(?:-?[^>-])(?:-?[^-])*-->"
const PROCESSING_INSTRUCTION = r"[<][?].*?[?][>]"
const DECLARATION = r"<![A-Z]+\s+[^>]*>"
const CDATA_SECTION = r"<!\[CDATA\[[\s\S]*?\]\]>"
const HTML_TAG = (
  r"(?:" &
  OPEN_TAG & "|" &
  CLOSE_TAG & "|" &
  HTML_COMMENT & "|" &
  PROCESSING_INSTRUCTION & "|" &
  DECLARATION & "|" &
  CDATA_SECTION &
  & r")"
)

const HTML_OPEN_CLOSE_TAG_START = " {0,3}(?:" & OPEN_TAG & "|" & CLOSE_TAG & r")\s*$"
const HTML_OPEN_CLOSE_TAG_END = r"^\n?$"
let HTML_SEQUENCES = @[
  (HTML_SCRIPT_START, HTML_SCRIPT_END),
  (HTML_COMMENT_START, HTML_COMMENT_END),
  (HTML_PROCESSING_INSTRUCTION_START, HTML_PROCESSING_INSTRUCTION_END),
  (HTML_DECLARATION_START, HTML_DECLARATION_END),
  (HTML_CDATA_START, HTML_CDATA_END),
  (HTML_TAG_START, HTML_TAG_END),
  (HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END),
]

proc `$`*(chunk: Chunk): string =
  fmt"{chunk.kind}{[chunk.doc]}"

proc replaceInitialTabs*(doc: string): string =
  var n: int
  for line in doc.splitLines(keepEol=true):
    n = 0
    for ch in line:
      if ch == '\t':
        n += 1
      else:
        break
    if n == 0:
      add result, line
    else:
      add result, " ".repeat(n*4)
      add result, substr(line, n, line.len)

proc preProcessing(state: State, token: Token) =
  token.doc = token.doc.replace(re"\r\n|\r", "\n")
  token.doc = token.doc.replace("\u2424", " ")
  token.doc = token.doc.replace("\u0000", "\uFFFD")
  token.doc = token.doc.replace("&#0;", "&#XFFFD;")
  token.doc = token.doc.replaceInitialTabs

proc isBlank(doc: string, start: int = 0, stop: int = 0): bool =
  let matchStop = if stop == 0: doc.len else: stop
  doc.matchLen(re"[ \t]*\n?$", start, matchStop) != -1

proc findFirstLine(doc: string, start: int): int =
  if start >= doc.len:
    return 0
  let pos = doc.find('\l', start)
  if pos == -1:
    return doc.len - start
  else:
    return pos - start # include eol

iterator findRestLines(doc: string, start: int): tuple[start: int, stop: int] =
  # left: open, right: closed
  var nextStart = start
  var nextEnd = start
  while nextStart < doc.len:
    nextEnd = doc.find('\l', nextStart)
    if nextEnd == -1:
      yield (nextStart, doc.len)
      break
    else:
      yield (nextStart, nextEnd+1)
    nextStart = nextEnd + 1

proc escapeTag(doc: string): string =
  ## Replace `<` and `>` to HTML-safe characters.
  ## Example::
  ##     check escapeTag("<tag>") == "&lt;tag&gt;"
  result = doc.replace("<", "&lt;")
  result = result.replace(">", "&gt;")

proc escapeQuote(doc: string): string =
  ## Replace `"` to HTML-safe characters.
  ## Example::
  ##     check escapeTag("'tag'") == "&quote;tag&quote;"
  doc.replace("\"", "&quot;")

proc escapeAmpersandChar(doc: string): string =
  ## Replace character `&` to HTML-safe characters.
  ## Example::
  ##     check escapeAmpersandChar("&amp;") ==  "&amp;amp;"
  result = doc.replace("&", "&amp;")

let reAmpersandSeq = re"&(?!#?\w+;)"

proc escapeAmpersandSeq(doc: string): string =
  ## Replace `&` from a sequence of characters starting from it to HTML-safe characters.
  ## It's useful to keep those have been escaped.
  ##
  ## Example::
  ##     check escapeAmpersandSeq("&") == "&"
  ##     escapeAmpersandSeq("&amp;") == "&amp;"
  result = doc.replace(sub=reAmpersandSeq, by="&amp;")

proc escapeCode(doc: string): string =
  ## Make code block in markdown document HTML-safe.
  result = doc.escapeAmpersandChar.escapeTag

proc removeBlankLines(doc: string): string =
  doc.strip(leading=false, trailing=true, chars={'\n'})

proc escapeInvalidHTMLTag(doc: string): string =
  doc.replacef(
    re(r"<(title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)>",
      {RegexFlag.reIgnoreCase}),
    "&lt;$1>")

const IGNORED_HTML_ENTITY = ["&lt;", "&gt;", "&amp;"]

proc escapeHTMLEntity(doc: string): string =
  var entities = doc.findAll(re"&([^;]+);")
  result = doc
  for entity in entities:
    if not IGNORED_HTML_ENTITY.contains(entity):
      let utf8Char = entity.htmlEntityToUtf8
      if utf8Char == "":
        result = result.replace(re(entity), entity.escapeAmpersandChar)
      else:
        result = result.replace(re(entity), utf8Char)

proc escapeLinkUrl(url: string): string =
  encodeUrl(url.escapeHTMLEntity, usePlus=false).multiReplace([
    ("%40", "@"),
    ("%3A", ":"),
    ("%3A", ":"),
    ("%2B", "+"),
    ("%3F", "?"),
    ("%3D", "="),
    ("%26", "&"),
    ("%28", "("),
    ("%29", ")"),
    ("%25", "%"),
    ("%23", "#"),
    ("%2A", "*"),
    ("%2C", ","),
    ("%2F", "/"),
  ])

proc escapeBackslash(doc: string): string =
  doc.replacef(re"\\([\\`*{}\[\]()#+\-.!_<>~|""$%&',/:;=?@^])", "$1")

proc reFmt(patterns: varargs[string]): Regex =
  var s: string
  for p in patterns:
    s &= p
  re(s)

method `$`*(token: Token): string {.base.} = ""

method `$`*(token: CodeSpan): string =
  code(token.doc.escapeAmpersandChar.escapeTag.escapeQuote)

method `$`*(token: SoftBreak): string = "\n"

method `$`*(token: HardBreak): string = br() & "\n"

method `$`*(token: Strikethrough): string =
  del(token.doc)

method `$`*(token: ThematicBreak): string =
  hr()

method `$`*(token: Escape): string =
  token.doc.escapeAmpersandSeq.escapeTag.escapeQuote

method `$`*(token: InlineHtml): string =
  token.doc.escapeInvalidHTMLTag

method `$`*(token: HtmlEntity): string =
  token.doc.escapeHTMLEntity.escapeQuote

method `$`*(token: Text): string =
  token.doc.escapeAmpersandChar.escapeTag.escapeQuote

method `$`*(token: AutoLink): string =
  let href = token.url.escapeLinkUrl.escapeAmpersandSeq
  let text = token.text.escapeAmpersandSeq
  a(href=href, text)

method `$`*(token: CodeBlock): string =
  var codeHTML = token.doc.escapeCode.escapeQuote
  if codeHTML != "" and not codeHTML.endsWith("\n"):
    codeHTML &= "\n"
  if token.info == "":
    pre(code(codeHTML))
  else:
    let info = token.info.escapeBackslash.escapeHTMLEntity
    let lang = "language-" & info
    pre(code(class=lang, codeHTML))

method `$`*(token: HtmlBlock): string =
  token.doc.strip(chars={'\n'})

method `$`*(token: Link): string =
  let href = token.url.escapeBackslash.escapeLinkUrl
  let title = token.title.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote
  if title == "": a(href=href, token.render(""))
  else: a(href=href, title=title, token.render(""))

proc toAlt*(token: Token): string =
  if (token of Em) or (token of Strong): token.render("")
  elif token of Link: Link(token).text
  elif token of Image: Image(token).alt
  else: $token

proc childrenToAlt(token: Token): string =
  for child in token.children:
    result &= child.toAlt

method `$`*(token: Image): string =
  let src = token.url.escapeBackslash.escapeLinkUrl
  let title=token.title.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote
  let alt = token.childrenToAlt()
  if title == "": img(src=src, alt=alt)
  else: img(src=src, alt=alt, title=title)

method `$`*(token: Em): string = em(token.render(""))

method `$`*(token: Strong): string = strong(token.render(""))

method `$`*(token: Paragraph): string =
  if token.children.head == nil: ""
  elif token.loose: p(token.render(""))
  else: token.render("")

method `$`*(token: Heading): string =
  let num = $token.level
  let child = token.render("")
  fmt"<h{num}>{child}</h{num}>"

method `$`*(token: THeadCell): string =
  let align = token.align
  let child = token.render("")
  if align == "": th(child)
  else: fmt("<th align=\"{align}\">{child}</th>")

method `$`*(token: TBodyCell): string =
  let align = token.align
  let child = token.render("")
  if align == "": td(child)
  else: fmt("<td align=\"{align}\">{child}</td>")

method `$`*(token: TableRow): string =
  let cells = token.render("\n")
  tr("\n", cells , "\n")

method `$`*(token: TBody): string =
  let rows = token.render("\n")
  tbody("\n", rows)

method `$`*(token: THead): string =
  let tr = $token.children.head.value # table>thead>tr
  thead("\n", tr, "\n")

method `$`*(token: HtmlTable): string =
  let thead = $token.children.head.value # table>thead
  var tbody = $token.children.tail.value
  if tbody != "": tbody = "\n" & tbody.strip
  table("\n", thead, tbody)

proc renderListItemChildren(token: Li): string =
  var html: string
  if token.children.head == nil: return ""

  for child_node in token.children.nodes:
    var child_token = child_node.value
    if child_token of Paragraph and not Paragraph(child_token).loose:
      if child_node.prev != nil:
        result &= "\n"
      result &= $child_token
      if child_node.next == nil:
        return result
    else:
      html = $child_token
      if html != "":
        result &= "\n"
        result &= html
  if token.loose or token.children.tail != nil:
    result &= "\n"

method `$`*(token: Li): string =
  li(renderListItemChildren(token)) & "\n"

method `$`*(token: Ol): string =
  if token.start != 1:
    ol(start = $token.start, "\n", render(token))
  else:
    ol("\n", render(token))

method `$`*(token: Ul): string =
  ul("\n", render(token))

method `$`*(token: Blockquote): string =
  let content = render(token)
  blockquote("\n", if content.len > 0: content & "\n" else: "")

proc render*(token: Token, sep = "\n"): string =
  for child in token.children:
    if result.len > 0 and not result.endsWith sep:
      result &= sep
    result &= $child

proc endsWithBlankLine(token: Token): bool =
  if token of Paragraph:
    Paragraph(token).trailing.len > 1
  elif token of Li:
    Li(token).verbatim.find(re"\n\n$") != -1
  else:
    token.doc.find(re"\n\n$") != -1

proc parseLoose(token: Token): bool =
  for node in token.children.nodes:
    if node.next != nil and node.value.endsWithBlankLine:
      return true
    for itemNode in node.value.children.nodes:
      if itemNode.next != nil and itemNode.value.endsWithBlankLine:
        return true
  return false

proc parseOrderedListItem*(doc: string, start=0, marker: var string, listItemDoc: var string, index: var int = 1): int =
  let markerRegex = re"(?P<leading> {0,3})(?<index>\d{1,9})(?P<marker>\.|\))(?: *$| *\n|(?P<indent> +)([^\n]+(?:\n|$)))"
  var matches: array[5, string]
  var pos = start

  var firstLineSize = doc.matchLen(markerRegex, matches, pos)
  if firstLineSize == -1:
    return -1

  pos += firstLineSize

  var leading = matches[0]
  if marker == "":
    marker = matches[2]
  if marker != matches[2]:
    return -1

  var indexString = matches[1]
  index = indexString.parseInt

  listItemDoc = matches[4]

  var indent = 1
  if matches[3].len > 1 and matches[3].len <= 4:
    indent = matches[3].len
  elif matches[3].len > 4:
    listItemDoc = matches[3][1 ..< matches[3].len] & listItemDoc

  var padding = indexString.len + marker.len + leading.len + indent

  var size = 0
  while pos < doc.len:
    size = doc.matchLen(re(r"(?:\s*| {" & $padding & r"}([^\n]*))(\n|$)"), matches, pos)
    if size != -1:
      listItemDoc &= matches[0]
      listItemDoc &= matches[1]
      if listItemDoc.startswith("\n") and matches[0] == "":
        pos += size
        break
    elif listItemDoc.find(re"\n{2,}$") == -1:
      var firstLineSize = findFirstLine(doc, pos)
      var firstLineEnd = pos + firstLineSize
      if isContinuationText(doc, pos, firstLineEnd):
        listItemDoc &= substr(doc, pos, firstLineEnd)
        size = firstLineSize
      else:
        break
    else:
      break

    pos += size

  return pos - start

proc parseUnorderedListItem*(doc: string, start=0, marker: var string, listItemDoc: var string): int =
  #  thematic break takes precedence over list item.
  if doc.matchLen(re(THEMATIC_BREAK_RE), start) != -1:
    return -1

  # OL needs to include <empty> as well.
  let markerRegex = re"(?P<leading> {0,3})(?P<marker>[*\-+])(?:(?P<empty> *(?:\n|$))|(?<indent>(?: +|\t+))([^\n]+(?:\n|$)))"
  var matches: array[5, string]
  var pos = start

  var firstLineSize = doc.matchLen(markerRegex, matches, pos)
  if firstLineSize == -1:
    return -1

  pos += firstLineSize

  var leading = matches[0]
  if marker == "":
    marker = matches[1]
  if marker != matches[1]:
    return -1

  if matches[2] != "":
    listItemDoc = "\n"
  else:
    listItemDoc = matches[4]

  var indent = 1
  if matches[3].contains(re"\t"):
    indent = 1
    listItemDoc = " ".repeat(matches[3].len * 4 - 2) & listItemDoc
  elif matches[3].len > 1 and matches[3].len <= 4:
    indent = matches[3].len
  elif matches[3].len > 4: # code block indent is still 1.
    listItemDoc = matches[3][1 ..< matches[3].len] & listItemDoc

  var padding = marker.len + leading.len + indent

  var size = 0
  while pos < doc.len:
    size = doc.matchLen(re(r"(?:[ \t]*| {" & $padding & r"}([^\n]*))(\n|$)"), matches, pos)
    if size != -1:
      listItemDoc &= matches[0]
      listItemDoc &= matches[1]
      if listItemDoc.startswith("\n") and matches[0] == "":
        pos += size
        break
    elif listItemDoc.find(re"\n{2,}$") == -1:
      var firstLineSize = findFirstLine(doc, pos)
      var firstLineEnd = pos + firstLineSize
      if isContinuationText(doc, pos, firstLineEnd):
        listItemDoc &= substr(doc, pos, firstLineEnd)
        size = firstLineSize
      else:
        break
    else:
      break

    pos += size

  return pos - start

method parse*(this: UlParser, doc: string, start: int): ParseResult =
  var pos = start
  var marker = ""
  var listItems: seq[Token]

  while pos < doc.len:
    var listItemDoc = ""
    var itemSize = parseUnorderedListItem(doc, pos, marker, listItemDoc)
    if itemSize == -1:
      break

    listItems.add Li(
      doc: listItemDoc.strip(chars={'\n'}),
      verbatim: listItemDoc,
      marker: marker
    )

    pos += itemSize

  if marker == "":
    return ParseResult(token: nil, pos: -1)

  var ulToken = Ul(
    doc: substr(doc, start, pos-1),
  )
  for listItem in listItems:
    ulToken.appendChild(listItem)

  return ParseResult(token: ulToken, pos: pos)

method parse*(this: OlParser, doc: string, start: int): ParseResult =
  var pos = start
  var marker = ""
  var startIndex = 1
  var found = false
  var index = 1
  var listItems: seq[Token]

  while pos < doc.len:
    var listItemDoc = ""
    var itemSize = parseOrderedListItem(doc, pos, marker, listItemDoc, index)
    if itemSize == -1:
      break
    if not found:
      startIndex = index
      found = true

    listItems.add Li(
      doc: listItemDoc.strip(chars={'\n'}),
      verbatim: listItemDoc,
      marker: marker
    )

    pos += itemSize

  if marker == "":
    return ParseResult(token: nil, pos: -1)

  var olToken = Ol(
    doc: substr(doc, start, pos-1),
    start: startIndex,
  )
  for listItem in listItems:
    olToken.appendChild(listItem)

  return ParseResult(token: olToken, pos: pos)

proc getThematicBreak(doc: string, start: int = 0): tuple[size: int] =
  return (size: doc.matchLen(re(THEMATIC_BREAK_RE), start))

method parse*(this: ThematicBreakParser, doc: string, start: int): ParseResult =
  let res = doc.getThematicBreak(start)
  if res.size == -1: return ParseResult(token: nil, pos: -1)
  return ParseResult(
    token: ThematicBreak(),
    pos: start+res.size
  )

proc getFence*(doc: string, start: int = 0): tuple[indent: int, fence: string, size: int] =
  var matches: array[2, string]
  let size = doc.matchLen(re"((?: {0,3})?)(`{3,}|~{3,})", matches, start)
  if size == -1: return (-1, "", -1)
  return (
    indent: matches[0].len,
    fence: substr(doc, start, start+size-1).strip,
    size: size
  )

proc parseCodeContent*(doc: string, indent: int, fence: string): tuple[code: string, size: int]=
  var closeSize = -1
  var pos = 0
  var codeContent = ""
  let closeRe = re(r"(?: {0,3})" & fence & $fence[0] & "{0,}( |\t)*(?:$|\n)")
  for line in doc.splitLines(keepEol=true):
    closeSize = line.matchLen(closeRe)
    if closeSize != -1:
      pos += closeSize
      break

    if line != "\n" and line != "":
      codeContent &= line.replacef(re(r"^ {0," & indent.intToStr & r"}([^\n]*)"), "$1")
    else:
      codeContent &= line
    pos += line.len
  return (codeContent, pos)

proc parseCodeInfo*(doc: string, start: int = 0): tuple[info: string, size: int] =
  var matches: array[1, string]
  let size = doc.matchLen(re"(?: |\t)*([^`\n]*)?(?:\n|$)", matches, start)
  if size == -1:
    return ("", -1)
  for item in matches[0].splitWhitespace:
    return (item, size)
  return ("", size)

proc parseTildeBlockCodeInfo*(doc: string, start: int = 0): tuple[info: string, size: int] =
  var matches: array[1, string]
  let size = doc.matchLen(re"(?: |\t)*(.*)?(?:\n|$)", matches, start)
  if size == -1:
    return ("", -1)
  for item in matches[0].splitWhitespace:
    return (item, size)
  return ("", size)

method parse*(this: FencedCodeParser, doc: string, start: int): ParseResult =
  var pos = start
  var fenceRes = doc.getFence(start)
  if fenceRes.size == -1: return ParseResult(token: nil, pos: -1)
  var indent = fenceRes.indent
  var fence = fenceRes.fence
  pos += fenceRes.size

  var infoSize = -1
  var info: string
  if fence.startsWith("`"):
    (info, infoSize) = doc.parseCodeInfo(pos)
  else:
    (info, infosize) = doc.parseTildeBlockCodeInfo(pos)
  if infoSize == -1: return ParseResult(token: nil, pos: -1)

  pos += infoSize

  var res = substr(doc, pos, doc.len-1).parseCodeContent(indent, fence)
  var codeContent = res.code
  pos += res.size

  if doc.matchLen(re"\n$", pos) != -1:
    pos += 1

  let codeToken = CodeBlock(
    doc: codeContent,
    info: info,
  )
  return ParseResult(token: codeToken, pos: pos)

const rIndentedCode = r"(?: {4}| {0,3}\t)(.*\n?)"

proc getIndentedCodeFirstLine*(doc: string, start: int = 0): tuple[code: string, size: int]=
  var matches: array[1, string]
  if matchLen(doc, re(rIndentedCode), matches, start) == -1: return ("", -1)
  if matches[0].isBlank: return ("", -1)
  return (code: matches[0], size: findFirstLine(doc, start)+1)

proc getIndentedCodeRestLines*(doc: string, start: int = 0): tuple[code: string, size: int] =
  var firstLineSize = findFirstLine(doc, start)
  var firstLineEnd = start + firstLineSize

  var code: string
  var size: int
  var matches: array[1, string]

  for slice in findRestLines(doc, firstLineEnd+1):
    if isBlank(doc, slice.start, slice.stop):
      add code, substr(doc, slice.start, slice.stop-1).replace(re"^ {0,4}", "")
      size += (slice.stop - slice.start)

    elif matchLen(doc, re(rIndentedCode), matches, slice.start, slice.stop) != -1:
      add code, matches[0]
      size += (slice.stop - slice.start)

    else:
      break
  return (code: code, size: size)

method parse*(this: IndentedCodeParser, doc: string, start: int): ParseResult =
  var res = getIndentedCodeFirstLine(doc, start)
  if res.size == -1: return ParseResult(token: nil, pos: -1)
  var code = res.code
  var pos = start + res.size
  res = getIndentedCodeRestLines(doc, start)
  code &= res.code
  code = code.removeBlankLines
  pos += res.size
  return ParseResult(
    token: CodeBlock(doc: code, info: ""),
    pos: pos
  )

proc parseIndentedCode*(doc: string, start: int): ParseResult =
  IndentedCodeParser().parse(doc, start)

proc getSetextHeading*(doc: string, start = 0): tuple[level: int, doc: string, size: int] =
  var firstLineSize = findFirstLine(doc, start)
  var firstLineEnd = start + firstLineSize
  var size = firstLineSize+1
  var markerLen = 0
  var matches: array[1, string]
  let pattern = re(r" {0,3}(=|-)+ *(?:\n+|$)")
  var level = 0

  for slice in findRestLines(doc, firstLineEnd+1):
    if matchLen(doc, re"(?:\n|$)", slice.start, slice.stop) != -1: # found empty line
      break
    if matchLen(doc, re" {4,}", slice.start, slice.stop) != -1: # found code block
      size += slice.stop - slice.start
      continue
    if matchLen(doc, pattern, matches, slice.start, slice.stop) != -1:
      markerLen = slice.stop - slice.start
      size += markerLen
      if matches[0] == "=":
        level = 1
      elif matches[0] == "-":
        level = 2
      break
    else:
      size += slice.stop - slice.start

  if level == 0:
    return (level: 0, doc: "", size: -1)

  if matchLen(doc, re"(?:\s*\n)+", start, start+size-markerLen) != -1:
    return (level: 0, doc: "", size: -1)

  let doc = substr(doc, start, start+size-markerLen-1).strip
  return (level: level, doc: doc, size: size)

method parse(this: SetextHeadingParser, doc: string, start: int): ParseResult =
  let res = getSetextHeading(doc, start)
  if res.size == -1: return ParseResult(token: nil, pos: -1)
  return ParseResult(
    token: Heading(
      doc: res.doc,
      level: res.level,
    ),
    pos: start+res.size
  )

const ATX_HEADING_RE = r" {0,3}(#{1,6})([ \t]+)?(?(2)([^\n]*?))([ \t]+)?(?(4)#*) *(?:\n+|$)"

proc getAtxHeading*(s: string, start: int = 0): tuple[level: int, doc: string, size: int] =
  var matches: array[4, string]
  let size = s.matchLen(re(ATX_HEADING_RE), matches, start)
  if size == -1:
    return (level: 0, doc: "", size: -1)

  let level = matches[0].len
  let doc = if matches[2] =~ re"#+": "" else: matches[2]
  return (level: level, doc: doc, size: size)

method parse(this: AtxHeadingParser, doc: string, start: int = 0): ParseResult =
  let res = doc.getAtxHeading(start)
  if res.size == -1: return ParseResult(token: nil, pos: -1)
  return ParseResult(
    token: Heading(
      doc: res.doc,
      level: res.level,
    ),
    pos: start+res.size
  )

method parse*(this: BlanklineParser, doc: string, start: int): ParseResult =
  let size = doc.matchLen(re(r"((?:\s*\n)+)"), start)
  if size == -1: return ParseResult(token: nil, pos: -1)
  let token = Token(doc: substr(doc, start, start+size-1))
  return ParseResult(token: token, pos: start+size)

proc parseBlankLine*(doc: string, start: int): ParseResult =
  BlanklineParser().parse(doc, start)

proc parseTableRow*(doc: string): seq[string] =
  var pos = 0
  var max = doc.len
  var ch: char
  var escapes = 0
  var lastPos = 0
  var backTicked = false
  var lastBackTick = 0

  if doc == "":
    return @[]

  ch = doc[pos]

  while pos < max:
    if ch == '`':
      if backTicked:
        backTicked = false
        lastBackTick = pos
      elif escapes mod 2 == 0:
        backTicked = true
        lastBackTick = pos
    elif ch == '|' and escapes mod 2 == 0 and not backTicked:
      add result, substr(doc, lastPos, pos-1)
      lastPos = pos + 1

    if ch == '\\':
      escapes += 1
    else:
      escapes = 0

    pos += 1

    if pos == max and backTicked:
      backTicked = false
      pos = lastBackTick + 1

    if pos < max:
      ch = doc[pos]

  add result, substr(doc, lastPos, max-1)

proc parseTableAligns*(doc: string): tuple[aligns: seq[string], matched: bool] =
  if not doc.match(re"^ {0,3}[-:|][-:|\s]*(?:\n|$)"):
    return (@[], false)
  var columns = doc.split("|")
  var aligns: seq[string]
  for index, column in columns:
    var t = column.strip
    if t == "":
      if index == 0 or index == columns.len - 1:
        continue
      else:
        return (@[], false)
    if not t.match(re"^:?-+:?$"):
      return (@[], false)
    if t[0] == ':':
      if t[t.len - 1] == ':':
        aligns.add("center")
      else:
        aligns.add("left")
    elif t[t.len - 1] == ':':
      aligns.add("right")
    else:
      aligns.add("")
  return (aligns, true)

method parse*(this: HtmlTableParser, doc: string, start: int): ParseResult =
  # Algorithm:
  # fail fast if less than 2 lines.
  # second line: /^[-:|][-:|\s]*$/
  # extract columns & aligns from the 2nd line.
  # extract columns & headers from the 1st line.
  # fail fast if align&header columns length not match.
  # construct thead
  # iterate the rest of lines.
  #   extract tbody
  # construct token.
  var pos = start
  let lines = substr(doc, start, doc.len-1).splitLines(keepEol=true)
  if lines.len < 2:
    return ParseResult(token: nil, pos: -1)

  var (aligns, alignsMatched) = lines[1].parseTableAligns
  if not alignsMatched:
    return ParseResult(token: nil, pos: -1)

  if lines[0].matchLen(re"^ {4,}") != -1:
    return ParseResult(token: nil, pos: -1)

  if lines[0] == "" or lines[0].find('|') == -1:
    return ParseResult(token: nil, pos: -1)

  var heads = parseTableRow(lines[0].replace(re"^\||\|$", ""))
  if heads.len > aligns.len:
    return ParseResult(token: nil, pos: -1)

  var theadToken = THead(
    doc: lines[0],
  )
  var theadRowToken = TableRow(
    doc: lines[0],
  )
  for index, elem in heads:
    var thToken = THeadCell(
      doc: elem.strip,
      align: aligns[index],
    )
    theadRowToken.appendChild(thToken)
  theadToken.appendChild(theadRowToken)

  pos += lines[0].len + lines[1].len

  var tbodyRows: seq[Token]
  for lineIndex, line in lines[2 ..< lines.len]:
    if line.matchLen(re"^ {4,}") != -1:
      break
    if line == "" or line.find('|') == -1:
      break

    var rowColumns = parseTableRow(line.replace(re"^\||\|$", ""))

    var tableRowToken = TableRow(
      doc: "",
    )
    for index, elem in heads:
      var doc = 
        if index >= rowColumns.len:
          ""
        else:
          rowColumns[index]
      var tdToken = TBodyCell(
        doc: doc.replace(re"\\\|", "|").strip,
        align: aligns[index],
      )
      tableRowToken.appendChild(tdToken)
    tbodyRows.add(tableRowToken)
    pos += line.len

  var tableToken = HtmlTable(
    doc: substr(doc, start, pos-1),
  )
  tableToken.appendChild(theadToken)
  if tbodyRows.len > 0:
    var tbodyStart = start+lines[0].len+lines[1].len
    var tbodyToken = TBody(
      doc: substr(doc, tbodyStart, pos-1),
      size: tbodyRows.len,
    )
    for tbodyRowToken in tbodyRows:
      tbodyToken.appendChild(tbodyRowToken)
    tableToken.appendChild(tbodyToken)
  return ParseResult(token: tableToken, pos: pos)

proc parseHTMLBlockContent*(doc: string, startPattern: string, endPattern: string,
  ignoreCase = false): tuple[html: string, size: int] =
  # Algorithm:
  # firstLine: detectOpenTag
  # fail fast.
  # firstLine: detectCloseTag
  # success fast.
  # rest of the lines:
  #   detectCloseTag
  #   success fast.
  var html = ""
  let startRe = if ignoreCase: re(startPattern, {RegexFlag.reIgnoreCase}) else: re(startPattern)
  let endRe = if ignoreCase: re(endPattern, {RegexFlag.reIgnoreCase}) else: re(endPattern)
  var pos = 0
  var size = -1
  let docLines = doc.splitLines(keepEol=true)
  if docLines.len == 0:
    return ("", -1)
  let firstLine = docLines[0]
  size = firstLine.matchLen(startRe)
  if size == -1:
    return ("", -1)
  html = firstLine
  size = firstLine.find(endRe)
  if size != -1:
    return (html, html.len)
  else:
    pos = firstLine.len
  for line in docLines[1 ..< docLines.len]:
    pos += line.len
    html &= line
    if line.find(endRe) != -1:
      break
  return (html, pos)

proc matchHtmlStart*(doc: string, start: int = 0, bufsize: int = 0): tuple[startRe: Regex, endRe: Regex, endMatch: bool, continuation: bool] =
  var startRe: Regex = nil
  var endRe: Regex = nil
  var endMatch = false
  var continuation = false

  for index, patterns in HTML_SEQUENCES:
    startRe = re(patterns[0], {RegexFlag.reIgnoreCase})
    let size = doc.matchLen(startRe, start, bufsize)
    if size != -1:
      continuation = index == 6 # HTML_OPEN_CLOSE_TAG_START/END
      if patterns[1][0] == '^':
        endRe = re(r"\n$")
        endMatch = true
      else:
        endRe = re(patterns[1], {RegexFlag.reIgnoreCase})
        endMatch = false
      break

  if endRe == nil:
    return (nil, nil, false, false)
  else:
    return (startRe, endRe, endMatch, continuation)

proc parseHtmlBlock(doc: string, start: int = 0): ParseResult =
  var pos = 0
  var size = -1

  let firstLineSize = findFirstLine(doc, start)
  let firstLineEnd = start + firstLineSize

  let matchStart = matchHtmlStart(doc, start, firstLineEnd)
  if matchStart.endRe == nil:
    return skipParsing

  var endRe: Regex = matchStart.endRe
  var endMatch = matchStart.endMatch

  if endMatch:
    size = doc.matchLen(endRe, start, firstLineEnd)
  else:
    size = doc.find(endRe, start, firstLineEnd)

  if size != -1:
    return ParseResult(
      token: HtmlBlock(doc: substr(doc, start, firstLineEnd)),
      pos: firstLineEnd
    )

  pos = firstLineSize+1

  for line in findRestLines(doc, firstLineEnd+1):
    if endMatch:
      size = doc.matchLen(endRe, line.start, line.stop)
    else:
      size = doc.find(endRe, line.start, line.stop)
    pos += (line.stop-line.start)
    if size != -1:
      break

  return ParseResult(
    token: HtmlBlock(doc: substr(doc, start, start+pos-1)),
    pos: start+pos
  )

method parse*(this: HtmlBlockParser, doc: string, start: int): ParseResult =
  return parseHtmlBlock(doc, start)

const rBlockquoteMarker = r"( {0,3}>)"

proc isBlockquote*(s: string, start: int = 0): bool =
  s.match(re(rBlockquoteMarker), start)

proc consumeBlockquoteMarker(doc: string): string =
  var r: string
  for line in doc.splitLines(keepEol=true):
    r = line.replacef(re"^ {0,3}>(.*)", "$1")
    if r.len == 0:
      continue
    case r[0]:
      of ' ':
        add result, substr(r, 1, r.len-1)
      of '\t':
        r = r.replaceInitialTabs
        add result, substr(r, 2, r.len-1)
      else:
        add result, r

method parse*(this: BlockquoteParser, doc: string, start: int): ParseResult =
  let markerContent = re(r"(( {0,3}>([^\n]*(?:\n|$)))+)")
  var matches: array[3, string]
  var pos = start
  var size = -1
  var document = ""
  var found = false
  var chunks: seq[Chunk]

  while pos < doc.len:
    size = doc.matchLen(markerContent, matches, pos)

    if size == -1:
      break

    found = true
    pos += size
    # extract content with blockquote mark
    var blockChunk = matches[0].consumeBlockquoteMarker
    chunks.add(Chunk(kind: BlockChunk, doc: blockChunk, pos: pos))
    document &= blockChunk

    # blank line in non-lazy content always breaks the blockquote.
    if matches[2].strip == "":
      document = document.strip(leading=false, trailing=true)
      break

    # find the empty line in lazy content
    if doc.find(re" {4,}[^\n]+\n", start, pos) != -1 and doc.matchLen(re"\n| {4,}|$", pos) > -1:
      break

    # TODO laziness only applies to when the tip token is a paragraph.
    # find the laziness text
    var lazyChunk: string
    for line in substr(doc, pos, doc.len-1).splitLines(keepEol=true):
      if line.isBlank: break
      if not line.isContinuationText: break
      lazyChunk &= line
      pos += line.len
      document &= line
    chunks.add(Chunk(kind: LazyChunk, doc: lazyChunk, pos: pos))

  if not found:
    return ParseResult(token: nil, pos: -1)

  let blockquote = Blockquote(
    doc: document,
    chunks: chunks,
  )
  return ParseResult(token: blockquote, pos: pos)

method parse*(this: ReferenceParser, doc: string, start: int): ParseResult =
  var pos = start

  var markStart = doc.matchLen(re" {0,3}\[", pos)
  if markStart == -1:
    return ParseResult(token: nil, pos: -1)

  pos += markStart - 1

  var (label, labelSize) = getLinkLabel(doc, pos)

  # Link should have matching ] for [.
  if labelSize == -1:
    return ParseResult(token: nil, pos: -1)

  # A link label must contain at least one non-whitespace character.
  if label.find(re"\S") == -1:
    return ParseResult(token: nil, pos: -1)

  # An inline link consists of a link text followed immediately by a left parenthesis (
  pos += labelSize # [link]

  if pos >= doc.len or doc[pos] != ':':
    return ParseResult(token: nil, pos: -1)
  pos += 1

  # parse whitespace
  var whitespaceLen = doc.matchLen(re"[ \t]*\n?[ \t]*", pos)
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse destination
  var (destinationSlice, destinationLen) = getLinkDestination(doc, pos)

  if destinationLen <= 0:
    return ParseResult(token: nil, pos: -1)

  pos += destinationLen

  # parse whitespace
  var whitespaces: array[1, string]
  whitespaceLen = doc.matchLen(re"([ \t]*\n?[ \t]*)", whitespaces, pos)
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse title (optional)
  var titleSlice: Slice[int]
  var titleLen = 0
  if pos<doc.len and (doc[pos] == '(' or doc[pos] == '\'' or doc[pos] == '"'):
    # at least one whitespace before the optional title.
    if not {' ', '\t', '\n'}.contains(doc[pos-1]):
      return ParseResult(token: nil, pos: -1)

    (titleSlice, titleLen) = getLinkTitle(doc, pos)
    if titleLen >= 0:
      pos += titleLen
      # link title may not contain a blank line
      if doc.find(re"\n{2,}", titleSlice.a, titleSlice.b) != -1:
        return ParseResult(token: nil, pos: -1)

    # parse whitespace, no more non-whitespace is allowed from now.
    whitespaceLen = doc.matchLen(re"\s*(?:\n|$)", pos)
    if whitespaceLen != -1:
      pos += whitespaceLen
    # title might have trailing characters, but the label and dest is already enough.
    # [foo]: /url
    # "title" ok
    elif whitespaces[0].contains("\n"):
      pos -= titleLen
      titleLen = -1
    else:
      return ParseResult(token: nil, pos: -1)

  # construct token
  var reference = Reference(
    doc: substr(doc, start, pos-1),
    text: label,
    url: substr(doc, destinationSlice.a, destinationSlice.b),
    title: if titleLen <= 0:
      ""
    else:
      substr(doc, titleSlice.a, titleSlice.b),
  )
  return ParseResult(token: reference, pos: pos)

proc isContinuationText*(doc: string, start: int = 0, stop: int = 0): bool =
  var matchStop = if stop == 0: doc.len else: stop

  let atxRes = getAtxHeading(doc, start)
  if atxRes.size != -1: return false

  let brRes = getThematicBreak(doc, start)
  if brRes.size != -1: return false

  let setextRes = getSetextHeading(doc, start)
  if setextRes.size != -1: return false

  let htmlRes = matchHtmlStart(doc, start, matchStop)
  if htmlRes.startRe != nil and not htmlRes.continuation: return false

  # Indented code cannot interrupt a paragraph.

  var fenceRes = getFence(doc, start)
  if fenceRes.size != -1: return false

  if isBlockquote(doc, start): return false

  var ulMarker: string
  var ulDoc: string
  if parseUnorderedListItem(doc, start, ulMarker, ulDoc) != -1: return false

  var olMarker: string
  var olDoc: string
  var olIndex: int
  let olOffset = parseOrderedListItem(doc, start, marker=olMarker,
    listItemDoc=olDoc, index=olIndex)
  if olOffset != -1: return false

  return true

proc isUlEmptyListItem*(doc: string, start: int = 0, stop: int = 0): bool =
  doc.matchLen(re" {0,3}(?:[\-+*]|\d+[.)])[ \t]*\n?$", start, stop) != -1

proc isOlNo1ListItem*(doc: string, start: int = 0, stop: int = 0): bool =
  (
    doc.matchLen(re" {0,3}\d+[.(][ \t]+[^\n]", start, stop) != -1 and
    doc.matchLen(re" {0,3}1[.)]", start, stop) == -1
  )

method parse*(this: ParagraphParser, doc: string, start: int): ParseResult =
  let firstLineSize = findFirstLine(doc, start)
  var firstLineEnd = start + firstLineSize

  var size: int = firstLineSize+1

  for slice in findRestLines(doc, firstLineEnd+1):
    # Special cases.
    # empty list item is continuation text
    # ol should start with 1.
    if isUlEmptyListItem(doc, slice.start, slice.stop) or isOlNo1ListItem(doc, slice.start, slice.stop):
      size += (slice.stop - slice.start)
      continue

    # Continuation text ends at a blank line.
    if isBlank(doc, slice.start, slice.stop):
      size += (slice.stop - slice.start)
      break

    if not isContinuationText(doc, slice.start, slice.stop):
      break

    size += (slice.stop - slice.start)

  var p = substr(doc, start, start+size-1)
  let trailing = p.findAll(re"\n*$").join()
  p = p.replace(re"\n\s*", "\n").strip

  return ParseResult(
    token: Paragraph(
      doc: p,
      loose: true,
      trailing: trailing,
    ),
    pos: start+size
  )


proc tipToken*(token: Token): Token =
  var tip: Token = token
  while tip.children.tail != nil:
    tip = tip.children.tail.value
  return tip

proc parseContainerBlock(state: State, token: Token): ParseResult =
  #var doc: string
  #for chunk in token.chunks:
  #  doc &= chunk.doc
  #parseBlock(state, token)
  var chunks: seq[Chunk]
  var pos: int
  if token of Blockquote:
    for chunk in Blockquote(token).chunks:
      chunks.add(chunk)
      pos = chunk.pos
      if chunk.kind == BlockChunk:
        token.doc = chunk.doc
        var t = Token(doc: chunk.doc)
        parseBlock(state, t)
        var p = t.children.head
        if p != nil and p.value of Paragraph and token.tipToken of Paragraph:
          token.tipToken.doc &= p.value.doc
          t.children.remove(p)
        for child in t.children:
          token.appendChild(child)
        if not (token.tipToken of Paragraph):
          break
      else:
        if not token.tipToken.doc.endsWith("\n"):
          token.tipToken.doc &= "\n"
        token.tipToken.doc &= chunk.doc.strip(chars={' '})
  return ParseResult(token: token, pos: pos)

proc finalizeList*(state: State, token: Token) =
  for listItem in token.children.items:
    if listItem.doc != "":
      parseBlock(state, listItem)

  let loose = token.parseLoose
  for listItem in token.children.items:
    for child in listItem.children.items:
      if child of Paragraph:
        Paragraph(child).loose = loose

method apply*(this: Token, state: State, res: ParseResult): ParseResult {.base.} =
  res

method apply*(this: Ul, state: State, res: ParseResult): ParseResult =
  state.finalizeList(res.token)
  res

method apply*(this: Ol, state: State, res: ParseResult): ParseResult =
  state.finalizeList(res.token)
  res

method apply*(this: Blockquote, state: State, res: ParseResult): ParseResult =
  state.parseContainerBlock(res.token)

method apply*(this: Reference, state: State, res: ParseResult): ParseResult =
  if not state.references.contains(this.text):
    state.references[this.text] = this
  res

proc parseBlock(state: State, token: Token) =
  var res: ParseResult
  while token.pos < token.doc.len:
    for blockParser in state.config.blockParsers:
      res = parse(blockParser, token.doc, token.pos)
      if res.pos != -1:
        res = res.token.apply(state, res)
        res.token.pos = res.pos
        token.appendChild(res.token)
        token.pos = res.pos
        break

    if res.pos == -1:
      raise newException(MarkdownError, "unknown rule.")

method parse*(this: TextParser, doc: string, start: int): ParseResult =
  result = ParseResult(pos: start)
  while result.pos < doc.len and doc[result.pos] in {'a'..'z', 'A'..'Z', '0'..'9', ' '}: inc result.pos
  while result.pos > start and doc[result.pos - 1] == ' ': dec result.pos
  result.token = Text(doc: substr(doc, start, max(result.pos - 1, start)))

method parse*(this: SoftBreakParser, doc: string, start: int): ParseResult =
  let size = doc.matchLen(re" \n *", start)
  if size == -1: return skipParsing
  let token = SoftBreak()
  return ParseResult(token: token, pos: start+size)

method parse*(this: AutoLinkParser, doc: string, start: int): ParseResult =
  if doc[start] != '<':
    return skipParsing

  let EMAIL_RE = r"<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>"
  var emailMatches: array[1, string]
  var size = doc.matchLen(re(EMAIL_RE, {RegexFlag.reIgnoreCase}), emailMatches, start)

  if size != -1:
    var url = emailMatches[0]
    let token = AutoLink(
      text: url,
      url: fmt"mailto:{url}"
    )
    return ParseResult(token: token, pos: start+size)

  let LINK_RE = r"<([a-zA-Z][a-zA-Z0-9+.\-]{1,31}):([^<>\x00-\x20]*)>"
  var linkMatches: array[2, string]
  size = doc.matchLen(re(LINK_RE, {RegexFlag.reIgnoreCase}), linkMatches, start)

  if size != -1:
    var schema = linkMatches[0]
    var uri = linkMatches[1]
    var token = AutoLink(
      text: fmt"{schema}:{uri}",
      url: fmt"{schema}:{uri}",
    )
    return ParseResult(token: token, pos: start+size)

  return skipParsing

proc scanInlineDelimiters*(doc: string, start: int, delimiter: var Delimiter) =
  var charBefore = '\n'
  var charAfter = '\n'
  let charCurrent = doc[start]
  var isCharAfterWhitespace = true
  var isCharBeforeWhitespace = true

  # get the number of delimiters.
  for ch in substr(doc, start, doc.len-1):
    if ch == charCurrent:
      delimiter.num += 1
      delimiter.originalNum += 1
    else:
      break

  # get the character before the starting character
  if start > 0:
    charBefore = doc[start - 1]
    isCharBeforeWhitespace = ($charBefore).match(re"^\s") or doc.runeAt(start - 1).isWhitespace

  # get the character after the delimiter runs
  if start + delimiter.num + 1 < doc.len:
    charAfter = doc[start + delimiter.num]
    isCharAfterWhitespace = ($charAfter).match(re"^\s") or doc.runeAt(start + delimiter.num).isWhitespace

  let isCharAfterPunctuation = ($charAfter).match(re"^\p{P}")
  let isCharBeforePunctuation = ($charBefore).match(re"^\p{P}")

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
    delimiter.canOpen = isLeftFlanking and ((not isRightFlanking) or isCharBeforePunctuation)
    delimiter.canClose = isRightFlanking and ((not isLeftFlanking) or isCharAfterPunctuation)
  else:
    delimiter.canOpen = isLeftFlanking
    delimiter.canClose = isRightFlanking

method parse*(this: DelimiterParser, doc: string, start: int): ParseResult =
  if not {'*', '_'}.contains(doc[start]):
    return ParseResult(token: nil, pos: -1)

  var delimiter = Delimiter(
    kind: $doc[start],
    num: 0,
    originalNum: 0,
    isActive: true,
    canOpen: false,
    canClose: false,
  )

  scanInlineDelimiters(doc, start, delimiter)
  if delimiter.num == 0:
    return ParseResult(token: nil, pos: -1)

  let size = delimiter.num
  let token = Text(
    doc: substr(doc, start, start+size-1),
    delimiter: delimiter
  )
  return ParseResult(token: token, pos: start+size)

proc getLinkDestination*(doc: string, start: int): tuple[slice: Slice[int], size: int] =
  # if start < 1 or doc[start - 1] != '(':
  #   raise newException(MarkdownError, fmt"{start} can not be the start of inline link destination.")

  # A link destination can be 
  # a sequence of zero or more characters between an opening < and a closing >
  # that contains no line breaks or unescaped < or > characters, or
  var size = -1
  var slice: Slice[int]

  if doc[start] == '<':
    size = doc.matchLen(re"<([^\n<>\\]*)>", start)
    if size != -1:
      slice.a = start + 1
      slice.b = start + size - 2
    return (slice, size)

  # A link destination can also be
  # a nonempty sequence of characters that does not include ASCII space or control characters, 
  # and includes parentheses only if 
  # (a) they are backslash-escaped or 
  # (b) they are part of a balanced pair of unescaped parentheses. 
  # (Implementations may impose limits on parentheses nesting to avoid performance issues, 
  # but at least three levels of nesting should be supported.)
  var level = 1 # assume the parenthesis has opened.
  var urlLen = 0
  var isEscaping = false
  for i, ch in substr(doc, start, doc.len-1):
    urlLen += 1
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true
      continue
    elif ch.int < 0x20 or ch.int == 0x7f or ch == ' ':
      urlLen -= 1
      break
    elif ch == '(':
      level += 1
    elif ch == ')':
      level -= 1
      if level == 0:
        urlLen -= 1
        break
  if level > 1:
    return ((0..<0), -1)
  if urlLen == -1:
    return ((0..<0), -1)
  return ((start ..< start+urlLen), urlLen)

proc getLinkTitle*(doc: string, start: int): tuple[slice: Slice[int], size: int] =
  var slice: Slice[int]
  var marker = doc[start]
  # Titles may be in single quotes, double quotes, or parentheses
  if marker != '"' and marker != '\'' and marker != '(':
    return ((0..<0), -1)
  if marker == '(':
    marker = ')'
  var isEscaping = false
  for i, ch in substr(doc, start+1, doc.len-1):
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true
      continue
    elif ch == marker:
      slice = (start+1 .. start+i)
      return (slice, i+2)
  return ((0..<0), -1)

proc normalizeLabel*(label: string): string =
  # One label matches another just in case their normalized forms are equal.
  # To normalize a label, strip off the opening and closing brackets,
  # perform the Unicode case fold, strip leading and trailing whitespace
  # and collapse consecutive internal whitespace to a single space.
  label.toLower.strip.replace(re"\s+", " ")

proc getLinkLabel*(doc: string, start: int): tuple[label: string, size: int] =
  var isEscaping = false
  var size = 0

  if doc[start] != '[':
    raise newException(MarkdownError, fmt"{doc[start]} cannot be the start of link label.")

  if start+1 >= doc.len:
    return ("", -1)

  for i, ch in substr(doc, start+1, doc.len-1):
    size += 1

    # A link label begins with a left bracket ([) and ends with the first right bracket (]) that is not backslash-escaped.
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true
    elif ch == ']':
      break

    # Unescaped square bracket characters are not allowed inside the opening and closing square brackets of link labels
    elif ch == '[':
      return ("", -1)

    # A link label can have at most 999 characters inside the square brackets.
    if size > 999:
      return ("", -1)

  return (
    normalizeLabel(substr(doc, start+1, start+size-1)),
    size+1
  )


proc getLinkText*(doc: string, start: int, allowNested: bool = false): tuple[slice: Slice[int], size: int] =
  # based on assumption: token.doc[start] = '['
  if doc[start] != '[':
    raise newException(MarkdownError, fmt"{start} is not [.")

  # A link text consists of a sequence of zero or more inline elements enclosed by square brackets ([ and ]).
  var level = 0
  var isEscaping = false
  var skip = 0
  for i, ch in substr(doc, start, doc.len-1):
    # Skip ahead for higher precedent matches like code spans, autolinks, and raw HTML tags.
    if skip > 0:
      skip -= 1
      continue

    # Brackets are allowed in the link text only if (a) they are backslash-escaped
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true

    # or (b) they appear as a matched pair of brackets, with an open bracket [,
    # a sequence of zero or more inlines, and a close bracket ].
    elif ch == '[':
      level += 1
    elif ch == ']':
      level -= 1

    # Backtick: code spans bind more tightly than the brackets in link text.
    # Skip the tokens in code.
    elif ch == '`':
      # FIXME: it's better to extract to a code span helper function
      skip = doc.matchLen(re"((`+)\s*([\s\S]*?[^`])\s*\2(?!`))", start+i) - 1

    # autolinks, and raw HTML tags bind more tightly than the brackets in link text.
    elif ch == '<':
      skip = doc.matchLen(re"<[^>]*>", start+i) - 1

    # Links may not contain other links, at any level of nesting.
    # Image description may contain links.
    if level == 0 and not allowNested and doc.find(re"[^!]\[[^]]*\]\([^)]*\)", start, start+i) > -1:
      return ((0..<0), -1)
    if level == 0 and not allowNested and doc.find(re"[^!]\[[^]]*\]\[[^]]*\]", start, start+i) > -1:
      return ((0..<0), -1)

    if level == 0:
      let slice = (start .. start+i)
      return (slice, i+1)

  return ((0..<0), -1)

method apply*(this: Link, state: State, res: ParseResult): ParseResult =
  if this.text == "":
    return skipParsing
  if this.refId != "":
    if not state.references.contains(this.refId):
      return skipParsing
    else:
      let reference = state.references[this.refId]
      this.url = reference.url
      this.title = reference.title

  this.doc = this.text
  state.parseLeafBlockInlines(this)
  res

proc parseInlineLink(doc: string, start: int, labelSlice: Slice[int]): ParseResult =
  if doc[start] != '[':
    return skipParsing

  var pos = labelSlice.b + 2 # [link](

  # parse whitespace
  var whitespaceLen = doc.matchLen(re"[ \t\n]*", pos)
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse destination
  var (destinationSlice, destinationLen) = getLinkDestination(doc, pos)

  if destinationLen == -1:
    return skipParsing

  pos += destinationLen

  # parse whitespace
  whitespaceLen = doc.matchLen(re"[\x{0020}\x{0009}\x{000A}\x{000B}\x{000C}\x{000D}]*", pos)
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse title (optional)
  if not {'(', '\'', '"', ')'}.contains(doc[pos]):
    return skipParsing

  var (titleSlice, titleLen) = getLinkTitle(doc, pos)

  if titleLen >= 0:
    pos += titleLen

  # parse whitespace
  whitespaceLen = doc.matchLen(re"[ \t\n]*", pos)
  pos += whitespaceLen

  # require )
  if pos >= doc.len:
    return skipParsing
  if doc[pos] != ')':
    return skipParsing

  # construct token
  var link = Link(
    doc: substr(doc, start, pos),
    text: substr(doc, labelSlice.a+1, labelSlice.b-1),
    url: substr(doc, destinationSlice.a, destinationSlice.b),
    title: if titleLen == -1:
      ""
    else:
      substr(doc, titleSlice.a, titleSlice.b)
  )
  return ParseResult(token: link, pos: pos+1)

proc parseFullReferenceLink(doc: string, start: int, labelSlice: Slice[int]): ParseResult =
  var pos = labelSlice.b + 1
  var (label, labelSize) = getLinkLabel(doc, pos)

  if labelSize == -1: return skipParsing

  pos += labelSize

  var link = Link(
    doc: substr(doc, start, pos-1),
    refId: label,
    text: substr(doc, labelSlice.a+1, labelSlice.b-1),
  )
  return ParseResult(token: link, pos: pos)

proc parseCollapsedReferenceLink(doc: string, start: int, label: Slice[int]): ParseResult =
  var text = substr(doc, label.a+1, label.b-1)
  var link = Link(
    doc: substr(doc, start, label.b),
    text: text,
    refId: text.toLower.replace(re"\s+", " ")
  )
  return ParseResult(token: link, pos: label.b + 3)

proc parseShortcutReferenceLink(doc: string, start: int, labelSlice: Slice[int]): ParseResult =
  let text = substr(doc, labelSlice.a+1, labelSlice.b-1)
  let id = text.toLower.replace(re"\s+", " ")
  var link = Link(
    doc: substr(doc, start, labelSlice.b),
    text: text,
    refId: id,
  )
  return ParseResult(token: link, pos: labelSlice.b + 1)

method parse*(this: LinkParser, doc: string, start: int): ParseResult =
  # Link should start with [
  if doc[start] != '[': return skipParsing

  var (labelSlice, labelSize) = getLinkText(doc, start)
  # Link should have matching ] for [.
  if labelSize == -1: return skipParsing

  # An inline link consists of a link text followed immediately by a left parenthesis (
  if labelSlice.b + 1 < doc.len and doc[labelSlice.b + 1] == '(':
    var res = doc.parseInlineLink(start, labelSlice)
    if res.pos != -1: return res

  # A collapsed reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document, followed by the string []. 
  if labelSlice.b + 2 < doc.len and substr(doc, labelSlice.b+1, labelSlice.b+2) == "[]":
    var res = doc.parseCollapsedReferenceLink(start, labelSlice)
    if res.pos != -1: return res

  # A full reference link consists of a link text immediately followed by a link label 
  # that matches a link reference definition elsewhere in the document.
  elif labelSlice.b + 1 < doc.len and doc[labelSlice.b + 1] == '[':
    return doc.parseFullReferenceLink(start, labelSlice)

  # A shortcut reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document and is not followed by [] or a link label.
  return doc.parseShortcutReferenceLink(start, labelSlice)

proc parseInlineImage(doc: string, start: int, labelSlice: Slice[int]): ParseResult =
  var pos = labelSlice.b + 2 # ![link](

  # parse whitespace
  var whitespaceLen = doc.matchLen(re"[ \t\n]*", pos)
  pos += whitespaceLen

  # parse destination
  var (destinationslice, destinationLen) = getLinkDestination(doc, pos)
  if destinationLen == -1: return skipParsing

  pos += destinationLen

  # parse whitespace
  whitespaceLen = doc.matchLen(re"[ \t\n]*", pos)
  pos += whitespaceLen

  # parse title (optional)
  if not {'(', '\'', '"', ')'}.contains(doc[pos]):
    return skipParsing

  var (titleSlice, titleLen) = getLinkTitle(doc, pos)

  if titleLen >= 0:
    pos += titleLen

  # parse whitespace
  whitespaceLen = doc.matchLen(re"[ \t\n]*", pos)
  pos += whitespaceLen

  # require )
  if pos >= doc.len:
    return skipParsing
  if doc[pos] != ')':
    return skipParsing

  # construct token
  var image = Image(
    doc: substr(doc, start-1, pos),
    allowNested: true,
    alt: substr(doc, labelSlice.a+1, labelSlice.b-1),
    url: substr(doc, destinationSlice.a, destinationSlice.b),
    title: if titleLen == -1:
      ""
    else:
      substr(doc, titleSlice.a, titleSlice.b),
  )

  return ParseResult(token: image, pos: pos+2)

proc parseFullReferenceImage(doc: string, start: int, altSlice: Slice[int]): ParseResult =
  var pos = altSlice.b + 1
  let (label, labelSize) = getLinkLabel(doc, pos)

  if labelSize == -1: return skipParsing

  pos += labelSize

  var alt = substr(doc, altSlice.a+1, altSlice.b-1)

  var image = Image(
    doc: substr(doc, start, pos-2),
    alt: alt,
    refId: label,
    allowNested: true
  )
  return ParseResult(token: image, pos: pos+1)

proc parseCollapsedReferenceImage(doc: string, start: int, labelSlice: Slice[int]): ParseResult =
  let alt = substr(doc, labelSlice.a+1, labelSlice.b-1)
  let id = alt.toLower.replace(re"\s+", " ")
  let pos = labelSlice.b + 3
  var image = Image(
    doc: substr(doc, start, labelSlice.b+1),
    alt: alt,
    refId: id,
  )
  return ParseResult(token: image, pos: pos)

proc parseShortcutReferenceImage(doc: string, start: int, labelSlice: Slice[int]): ParseResult =
  let alt = substr(doc, labelSlice.a+1, labelSlice.b-1)
  let id = alt.toLower.replace(re"\s+", " ")
  let image = Image(
    doc: substr(doc, start, labelSlice.b),
    alt: alt,
    refId: id,
    allowNested: false,
  )
  return ParseResult(token: image, pos: labelSlice.b+1)

method apply*(this: Image, state: State, res: ParseResult): ParseResult =
  if this.refId != "":
    if not state.references.contains(this.refId):
      return skipParsing
    else:
      let reference = state.references[this.refId]
      this.url = reference.url
      this.title = reference.title

  this.doc = this.alt
  state.parseLeafBlockInlines(this)
  res

method parse*(this: ImageParser, doc: string, start: int): ParseResult =
  # Image should start with ![
  if not doc.match(re"!\[", start): return skipParsing

  var (labelSlice, labelSize) = getLinkText(doc, start+1, allowNested=true)

  # Image should have matching ] for [.
  if labelSize == -1: return skipParsing

  # An inline image consists of a link text followed immediately by a left parenthesis (
  if labelSlice.b + 1 < doc.len and doc[labelSlice.b + 1] == '(':
    return doc.parseInlineImage(start+1, labelSlice)

  # A collapsed reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document, followed by the string []. 
  elif labelSlice.b + 2 < doc.len and substr(doc, labelSlice.b+1, labelSlice.b+2) == "[]":
    return doc.parseCollapsedReferenceImage(start, labelSlice)

  # A full reference link consists of a link text immediately followed by a link label 
  # that matches a link reference definition elsewhere in the document.
  if labelSlice.b + 1 < doc.len and doc[labelSlice.b + 1] == '[':
    return doc.parseFullReferenceImage(start, labelSlice)

  # A shortcut reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document and is not followed by [] or a link label.
  return doc.parseShortcutReferenceImage(start, labelSlice)

const ENTITY = r"&(?:#x[a-f0-9]{1,6}|#[0-9]{1,7}|[a-z][a-z0-9]{1,31});"
method parse*(this: HtmlEntityParser, doc: string, start: int): ParseResult =
  if doc[start] != '&': return skipParsing

  let regex = re(r"(" & ENTITY & ")", {RegexFlag.reIgnoreCase})
  var matches: array[1, string]

  var size = doc.matchLen(regex, matches, start)
  if size == -1: return skipParsing

  var entity: string
  if matches[0] == "&#0;":
    entity = "\uFFFD"
  else:
    entity = escapeHTMLEntity(matches[0])

  let token = HtmlEntity(
    doc: entity
  )
  return ParseResult(token: token, pos: start+size)

method parse*(this: EscapeParser, doc: string, start: int): ParseResult =
  if doc[start] != '\\': return skipParsing

  let regex = re"\\([\\`*{}\[\]()#+\-.!_<>~|""$%&',/:;=?@^])"
  let size = doc.matchLen(regex, start)
  if size == -1: return skipParsing

  let token = Escape(doc: $doc[start+1])
  return ParseResult(token: token, pos: start+size)

method parse*(this: InlineHtmlParser, doc: string, start: int): ParseResult =
  if doc[start] != '<': return skipParsing

  let regex = re("(" & HTML_TAG & ")", {RegexFlag.reIgnoreCase})
  var matches: array[5, string]
  var size = doc.matchLen(regex, matches, start)

  if size == -1: return skipParsing

  let token = InlineHtml(doc: matches[0])
  return ParseResult(token: token, pos: start+size)

method parse*(this: HardBreakParser, doc: string, start: int): ParseResult =
  if not {' ', '\\'}.contains(doc[start]): return skipParsing
  let size = doc.matchLen(re"((?: {2,}\n|\\\n)\s*)", start)
  if size == -1: return skipParsing
  return ParseResult(token: HardBreak(), pos: start+size)

method parse*(this: CodeSpanParser, doc: string, start: int): ParseResult =
  if doc[start] != '`': return skipParsing

  var matches: array[5, string]
  var size = doc.matchLen(re"((`+)([^`]|[^`][\s\S]*?[^`])\2(?!`))", matches, start)

  if size == -1:
    size = doc.matchLen(re"`+(?!`)", start)
    if size == -1:
      return skipParsing
    let token = Text(doc: substr(doc, start, start+size-1))
    return ParseResult(token: token, pos: start+size)

  var codeSpanVal = matches[2].strip(chars={'\n'}).replace(re"[\n]+", " ")

  if codeSpanVal != "" and codeSpanVal[0] == ' ' and codeSpanVal[codeSpanVal.len-1] == ' ' and not codeSpanVal.match(re"^[ ]+$"):
    codeSpanVal = codeSpanVal[1 ..< codeSpanVal.len-1]

  let token = CodeSpan(doc: codeSpanVal)
  return ParseResult(token: token, pos: start+size)

method parse*(this: StrikethroughParser, doc: string, start: int): ParseResult =
  if doc[start] != '~': return skipParsing

  var matches: array[5, string]
  var size = doc.matchLen(re"(~~(?=\S)([\s\S]*?\S)~~)", matches, start)

  if size == -1: return skipParsing

  let token = Strikethrough(doc: matches[1])
  return ParseResult(token: token, pos: start+size)

proc removeDelimiter*(delimiter: var DoublyLinkedNode[Delimiter]) =
  if delimiter.prev != nil:
    delimiter.prev.next = delimiter.next
  if delimiter.next != nil:
    delimiter.next.prev = delimiter.prev
  delimiter = delimiter.next

proc getDelimiterStack*(token: Token): DoublyLinkedList[Delimiter] =
  result = initDoublyLinkedList[Delimiter]()
  for child in token.children.mitems:
    if child of Text:
      var text = Text(child)
      if text.delimiter != nil:
        text.delimiter.token = text # TODO: use treat delimiter as a token, instead of linking to a text token.
        result.append(text.delimiter)

proc processEmphasis*(state: State, token: Token) =
  var delimiterStack = token.getDelimiterStack
  var opener: DoublyLinkedNode[Delimiter] = nil
  var closer: DoublyLinkedNode[Delimiter] = nil
  var oldCloser: DoublyLinkedNode[Delimiter] = nil
  var openerFound = false
  var oddMatch = false
  var useDelims = 0
  var underscoreOpenerBottom: DoublyLinkedNode[Delimiter] = nil
  var asteriskOpenerBottom: DoublyLinkedNode[Delimiter] = nil

  # find first closer above stack_bottom
  #
  # *opener and closer*
  #                   ^
  closer = delimiterStack.head
  # move forward, looking for closers, and handling each
  while closer != nil:
    # find the first closing delimiter.
    #
    # sometimes, the delimiter **can _not** close.
    #                                ^
    # , so we choose jumping to the next ^
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
      ) and (
        closer.value.originalNum mod 3 != 0
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
      openerInlineText.doc = substr(openerInlineText.doc, 0, openerInlineText.doc.len-useDelims-1)
      closerInlineText.doc = substr(closerInlineText.doc, 0, closerInlineText.doc.len-useDelims-1)

      # build contents for new emph element
      # add emph element to tokens
      var emToken: Token
      if useDelims == 2:
        emToken = Strong()
      else:
        emToken = Em()

      var emNode = newDoublyLinkedNode(emToken)
      for childNode in token.children.nodes:
        if childNode.value == opener.value.token:
          emToken.children.head = childNode.next
          if childNode.next != nil:
            childNode.next.prev = nil
          childNode.next = emNode
          emNode.prev = childNode
        if childNode.value == closer.value.token:
          emToken.children.tail = childNode.prev
          if childNode.prev != nil:
            childNode.prev.next = nil
          childNode.prev = emNode
          emNode.next = childNode

      # remove elts between opener and closer in delimiters stack
      if opener != nil and opener.next != closer:
        opener.next = closer
        closer.prev = opener

      for childNode in token.children.nodes:
        if opener != nil and childNode.value == opener.value.token:
          # remove opener if no text left
          if opener.value.num == 0:
            removeDelimiter(opener)
        if closer != nil and childNode.value == closer.value.token:
          # remove closer if no text left
          if closer.value.num == 0:
            var tmp = closer.next
            removeDelimiter(closer)
            closer = tmp

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
        removeDelimiter(oldCloser)

  # after done, remove all delimiters
  while delimiterStack.head != nil:
    removeDelimiter(delimiterStack.head)

proc applyInlineParsers(state: State, doc: string, start: int): ParseResult =
  result = new(ParseResult)
  result.pos = -1
  for inlineParser in state.config.inlineParsers:
    result = inlineParser.parse(doc, start)
    if result.pos != -1:
      result = result.token.apply(state, result)
    if result.pos != -1:
      break
  if doc.len > 0 and result.pos == start:
    result = ParseResult(token: Text(doc: $doc[start]), pos: start + 1)

proc parseLeafBlockInlines(state: State, token: Token) =
  var pos = 0
  let doc = token.doc.strip
  while pos < doc.len:
    let res = state.applyInlineParsers(token.doc, pos)
    pos = res.pos
    res.token.pos = token.pos - token.doc.len + pos
    token.appendChild(res.token)
  processEmphasis(state, token)

proc isContainerToken(token: Token): bool =
  if token of Inline: return false
  if token of Document: return true
  if token of Block: return token.children.head != nil

proc parseInline(state: State, token: Token) =
  if isContainerToken(token):
    for childToken in token.children.mitems:
      parseInline(state, childToken)
  else:
    parseLeafBlockInlines(state, token)

proc parse(state: State, token: Token) =
  preProcessing(state, token)
  parseBlock(state, token)
  parseInline(state, token)

proc initCommonmarkConfig*(
  escape = true,
  keepHtml = true,
  blockParsers = @[
    ReferenceParser(),
    ThematicBreakParser(),
    BlockquoteParser(),
    UlParser(),
    OlParser(),
    IndentedCodeParser(),
    FencedCodeParser(),
    HtmlBlockParser(),
    AtxHeadingParser(),
    SetextHeadingParser(),
    BlanklineParser(),
    ParagraphParser(),
  ],
  inlineParsers = @[
    DelimiterParser(),
    ImageParser(),
    AutoLinkParser(),
    LinkParser(),
    HtmlEntityParser(),
    InlineHtmlParser(),
    EscapeParser(),
    CodeSpanParser(),
    HardBreakParser(),
    SoftBreakParser(),
    TextParser(),
  ]
): MarkdownConfig =
  result = MarkdownConfig(
    escape: escape,
    keepHtml: keepHtml,
    blockParsers: blockParsers,
    inlineParsers: inlineParsers,
  )

proc initGfmConfig*(
  escape = true,
  keepHtml = true,
  blockParsers = @[
    ReferenceParser(),
    ThematicBreakParser(),
    BlockquoteParser(),
    UlParser(),
    OlParser(),
    IndentedCodeParser(),
    FencedCodeParser(),
    HtmlBlockParser(),
    HtmlTableParser(),
    AtxHeadingParser(),
    SetextHeadingParser(),
    BlanklineParser(),
    ParagraphParser(),
  ],
  inlineParsers = @[
    DelimiterParser(),
    ImageParser(),
    AutoLinkParser(),
    LinkParser(),
    HtmlEntityParser(),
    InlineHtmlParser(),
    EscapeParser(),
    StrikethroughParser(),
    CodeSpanParser(),
    HardBreakParser(),
    SoftBreakParser(),
    TextParser(),
  ]
): MarkdownConfig =
  result = MarkdownConfig(
    escape: escape,
    keepHtml: keepHtml,
    blockParsers: blockParsers,
    inlineParsers: inlineParsers,
  )

proc markdown*(doc: string, config: MarkdownConfig = nil,
  root: Token = Document()): string =
  ## Convert a markdown document into a HTML document.
  ##
  ## config:
  ## * You can set `config=initCommonmarkConfig()` to apply commonmark syntax (default).
  ## * Or, set `config=initGfmConfig()` to apply GFM syntax.
  ##
  ## root:
  ## * You can set `root=Document()` (default).
  ## * Or, set root to any other token types, such as `root=Blockquote()`, or even your customized Token types, such as `root=Div()`.
  var conf = if config == nil: initCommonmarkConfig() else: config
  let references = initTable[string, Reference]()
  let state = State(references: references, config: conf)
  root.doc = doc.strip(chars={'\n'})
  state.parse(root)
  result = root.render()
  if result.len > 0 and not result.endsWith "\n":
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
  result = initCommonmarkConfig()
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
  stdout.write(
    markdown(
      stdin.readAll,
      config=readCLIOptions()
    )
  )


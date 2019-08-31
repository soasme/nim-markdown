import re, strutils, strformat, tables, sequtils, math, uri, htmlparser, lists
import unicode except `strip`, `splitWhitespace`
from sequtils import map
from lists import DoublyLinkedList, prepend, append
from htmlgen import nil, p, br, em, strong, a, img, code, del, blockquote, li, ul, ol, pre, code, table, thead, tbody, th, tr, td

type
  MarkdownError* = object of Exception ## The error object for markdown parsing and rendering.

  MarkdownConfig* = object ## Options for configuring parsing or rendering behavior.
    escape: bool ## escape ``<``, ``>``, and ``&`` characters to be HTML-safe
    keepHtml: bool ## deprecated: preserve HTML tags rather than escape it

  RuleSet = object
    preProcessingRules: seq[TokenType]
    blockRules: seq[TokenType]
    inlineRules: seq[TokenType]
    postProcessingRules: seq[TokenType]

  Delimiter* = object
    token: Token
    kind: string
    num: int
    originalNum: int
    isActive: bool
    canOpen: bool
    canClose: bool

  Paragraph = object
    doc: string

  Reference = object
    text: string
    title: string
    url: string

  Link = object 
    text: string ## A link contains link text (the visible text).
    url: string ## A link contains destination (the URI that is the link destination).
    title: string ## A link contains a optional title.

  Image = object
    url: string
    alt: string
    title: string

  AutoLink = object
    text: string
    url: string

  Blockquote = object
    doc: string

  UnorderedList = object
    loose: bool

  OrderedList = object
    loose: bool
    start: int

  ListItem = object
    loose: bool
    marker: string

  Heading = object
    level: int

  Fenced = object
    info: string

  HTMLTableCell = object
    align: string
    i: int
    j: int

  HTMLTableRow = object
    th: bool
    td: bool

  HTMLTable = object
    aligns: seq[string]

  HTMLTableHead = object
    size: int

  HTMLTableBody = object
    size: int

  TokenType* {.pure.} = enum
    ParagraphToken,
    ATXHeadingToken,
    SetextHeadingToken,
    ThematicBreakToken,
    IndentedCodeToken,
    FencedCodeToken,
    BlockquoteToken,
    HTMLBlockToken,
    TableToken,
    THeadToken,
    TBodyToken,
    TableRowToken,
    THeadCellToken,
    TBodyCellToken
    BlankLineToken,
    UnorderedListToken,
    OrderedListToken,
    ListItemToken,
    ReferenceToken,
    TextToken,
    AutoLinkToken,
    LinkToken,
    ImageToken,
    EmphasisToken,
    HTMLEntityToken,
    InlineHTMLToken,
    CodeSpanToken,
    StrongToken,
    EscapeToken,
    StrikethroughToken
    SoftLineBreakToken,
    HardLineBreakToken,
    DocumentToken

  Token* = ref object
    doc: string
    children: DoublyLinkedList[Token]
    case type*: TokenType
    of ParagraphToken: paragraphVal*: Paragraph
    of ATXHeadingToken: atxHeadingVal*: Heading
    of SetextHeadingToken: setextHeadingVal*: Heading
    of ThematicBreakToken: hrVal*: string
    of BlankLineToken: blankLineVal*: string
    of HTMLBlockToken: htmlBlockVal*: string
    of IndentedCodeToken: indentedCodeVal*: string
    of FencedCodeToken: fenceCodeVal*: Fenced
    of BlockquoteToken: blockquoteVal*: Blockquote
    of UnorderedListToken: ulVal*: UnorderedList
    of OrderedListToken: olVal*: OrderedList
    of ListItemToken: listItemVal*: ListItem
    of TableToken: tableVal*: HTMLTable
    of THeadToken: theadVal: HTMLTableHead
    of TBodyToken: tbodyVal: HTMLTableBody
    of TableRowToken: tableRowVal: HTMLTableRow
    of THeadCellToken: theadCellVal*: HTMLTableCell
    of TBodyCellToken: tbodyCellVal*: HTMLTableCell
    of ReferenceToken: referenceVal*: Reference
    of TextToken: textVal*: string
    of EmphasisToken: emphasisVal*: string
    of AutoLinkToken: autoLinkVal*: AutoLink
    of LinkToken: linkVal*: Link
    of EscapeToken: escapeVal*: string
    of InlineHTMLToken: inlineHTMLVal*: string
    of ImageToken: imageVal*: Image
    of HTMLEntityToken: htmlEntityVal*: string
    of CodeSpanToken: codeSpanVal*: string
    of StrongToken: strongVal*: string
    of StrikethroughToken: strikethroughVal*: string
    of SoftLineBreakToken: softLineBreakVal*: string
    of HardLineBreakToken: hardLineBreakVal*: string
    of DocumentToken: documentVal*: string

  ParseResult* = tuple[token: Token, pos: int]

  State* = ref object
    doc: string
    pos: int
    ruleSet: RuleSet
    loose: bool
    references: Table[string, Reference]
    tokens: DoublyLinkedList[Token]

var gfmRuleSet = RuleSet(
  preProcessingRules: @[],
  blockRules: @[
    ReferenceToken,
    ThematicBreakToken,
    BlockquoteToken,
    UnorderedListToken,
    OrderedListToken,
    IndentedCodeToken,
    FencedCodeToken,
    HTMLBlockToken,
    TableToken,
    BlankLineToken,
    ATXHeadingToken,
    SetextHeadingToken,
    ParagraphToken,
  ],
  inlineRules: @[
    EmphasisToken, # including strong.
    ImageToken,
    AutoLinkToken,
    LinkToken,
    HTMLEntityToken,
    InlineHTMLToken,
    EscapeToken,
    CodeSpanToken,
    StrikethroughToken,
    HardLineBreakToken,
    SoftLineBreakToken,
    TextToken,
  ],
  postProcessingRules: @[],
)

const THEMATIC_BREAK_RE* = r" {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*(?:\n+|$)"
const SETEXT_HEADING_RE* = r"((?:(?:[^\n]+)\n)+) {0,3}(=|-)+ *(?:\n+|$)"
const INDENTED_CODE_RE* = r"((?: {4}| {0,3}\t)[^\n]+\n*)+"

let HTML_SCRIPT_START* = r"^ {0,3}<(script|pre|style)(?=(\s|>|$))"
let HTML_SCRIPT_END* = r"</(script|pre|style)>"
let HTML_COMMENT_START* = r"^ {0,3}<!--"
let HTML_COMMENT_END* = r"-->"
let HTML_PROCESSING_INSTRUCTION_START* = r"^ {0,3}<\?"
let HTML_PROCESSING_INSTRUCTION_END* = r"\?>"
let HTML_DECLARATION_START* = r"^ {0,3}<\![A-Z]"
let HTML_DECLARATION_END* = r">"
let HTML_CDATA_START* = r" {0,3}<!\[CDATA\["
let HTML_CDATA_END* = r"\]\]>"
let HTML_VALID_TAGS* = ["address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "meta", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "section", "source", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"]
let HTML_TAG_START* = r"^ {0,3}</?(" & HTML_VALID_TAGS.join("|") & r")(?=(\s|/?>|$))"
let HTML_TAG_END* = r"^\n?$"

const TAGNAME* = r"[A-Za-z][A-Za-z0-9-]*"
const ATTRIBUTENAME* = r"[a-zA-Z_:][a-zA-Z0-9:._-]*"
const UNQUOTEDVALUE* = r"[^""'=<>`\x00-\x20]+"
const DOUBLEQUOTEDVALUE* = """"[^"]*""""
const SINGLEQUOTEDVALUE* = r"'[^']*'"
const ATTRIBUTEVALUE* = "(?:" & UNQUOTEDVALUE & "|" & SINGLEQUOTEDVALUE & "|" & DOUBLEQUOTEDVALUE & ")"
const ATTRIBUTEVALUESPEC* = r"(?:\s*=" & r"\s*" & ATTRIBUTEVALUE & r")"
const ATTRIBUTE* = r"(?:\s+" & ATTRIBUTENAME & ATTRIBUTEVALUESPEC & r"?)"
const OPEN_TAG* = r"<" & TAGNAME & ATTRIBUTE & r"*" & r"\s*/?>"
const CLOSE_TAG* = r"</" & TAGNAME & r"\s*[>]"
const HTML_COMMENT* = r"<!---->|<!--(?:-?[^>-])(?:-?[^-])*-->"
const PROCESSING_INSTRUCTION* = r"[<][?].*?[?][>]"
const DECLARATION* = r"<![A-Z]+\s+[^>]*>"
const CDATA_SECTION* = r"<!\[CDATA\[[\s\S]*?\]\]>"
const HTML_TAG* = (
  r"(?:" &
  OPEN_TAG & "|" &
  CLOSE_TAG & "|" &
  HTML_COMMENT & "|" &
  PROCESSING_INSTRUCTION & "|" &
  DECLARATION & "|" &
  CDATA_SECTION &
  & r")"
)

let HTML_OPEN_CLOSE_TAG_START* = "^ {0,3}(?:" & OPEN_TAG & "|" & CLOSE_TAG & r")\s*$"
let HTML_OPEN_CLOSE_TAG_END* = r"^\n?$"

proc parse(state: State, token: Token);
proc parseBlock(state: State, token: Token);
proc parseLeafBlockInlines(state: State, token: Token);
proc parseLinkInlines*(state: State, token: Token, allowNested: bool = false);
proc getLinkText*(doc: string, start: int, slice: var Slice[int], allowNested: bool = false): int;
proc getLinkLabel*(doc: string, start: int, label: var string): int;
proc getLinkDestination*(doc: string, start: int, slice: var Slice[int]): int;
proc getLinkTitle*(doc: string, start: int, slice: var Slice[int]): int;
proc render(state: State, token: Token): string;

proc since*(s: string, i: int, offset: int = -1): string =
  if offset == -1: s[i..<s.len] else: s[i..<i+offset]

proc replaceInitialTabs*(doc: string): string =
  var res: seq[string]
  var n: int
  for line in doc.splitLines(keepEol=true):
    n = 0
    for ch in line:
      if ch == '\t':
        n += 1
      else:
        break
    res.add(" ".repeat(n*4) & line[n..<line.len])
  return res.join("")

proc preProcessing(state: State, token: Token) =
  token.doc = token.doc.replace(re"\r\n|\r", "\n")
  token.doc = token.doc.replace("\u2424", " ")
  token.doc = token.doc.replace("\u0000", "\uFFFD")
  token.doc = token.doc.replace("&#0;", "&#XFFFD;")
  token.doc = token.doc.replaceInitialTabs
  # FIXME: it will aggressively clean empty line in code. 98
  #token.doc = token.doc.replace(re(r"^ +$", {RegexFlag.reMultiLine}), "")

proc isBlank*(doc: string): bool =
  doc.contains(re"^[ \t]*\n?$")

proc firstLine*(doc: string): string =
  for line in doc.splitLines(keepEol=true):
    return line
  return ""

iterator restLines*(doc: string): string =
  var isRestLines = false
  for line in doc.splitLines(keepEol=true):
    if isRestLines:
      yield line
    else:
      isRestLines = true

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

proc removeBlankLines*(doc: string): string =
  doc.strip(leading=false, trailing=true, chars={'\n'})

proc escapeInvalidHTMLTag(doc: string): string =
  doc.replacef(
    re(r"<(title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)>",
      {RegexFlag.reIgnoreCase}),
    "&lt;$1>")

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

let LAZINESS_TEXT = r"(?:(?! {0,3}>| {0,3}(?:\*|\+|-) | {0,3}\d+(?:\.|\)) | {0,3}#| {0,3}`{3,}| {0,3}\*{3}| {0,3}-{3}| {0,3}_{3})[^\n]+(?:\n|$))+"

const rThematicBreakLeading* = r" {0,3}"
const rThematicBreakMarker* = r"[-*_]"
const rThematicBreakSpace* = r"[ \t]"
const rFencedCodeLeading* = " {0,3}"
const rFencedCodeMarker* = r"(`{3,}|~{3,})"
const rFencedCodePadding* = r"(?: |\t)*"
const rFencedCodeInfo* = r"([^`\n]*)?"

proc reFmt*(patterns: varargs[string]): Regex =
  var s: string
  for p in patterns:
    s &= p
  re(s)

proc parseParagraph(doc: string, start: int): ParseResult =
  let size = doc.since(start).matchLen(
    re(r"^((?:[^\n]+\n?)(" & LAZINESS_TEXT & "|\n*))"),
  )
  if size == -1: return (nil, -1)
  return (
    token: Token(
      type: ParagraphToken,
      doc: doc[start ..< start+size].replace(re"\n\s*", "\n").strip,
      paragraphVal: Paragraph(
        doc: doc[start ..< start+size]
      )
    ),
    pos: start+size
  )

proc endsWithBlankLine(token: Token): bool =
  if token.type == ParagraphToken:
    token.paragraphVal.doc.find(re"\n\n$") != -1
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
  let markerRegex = re"^(?P<leading> {0,3})(?<index>\d{1,9})(?P<marker>\.|\))(?: *$| *\n|(?P<indent> +)([^\n]+(?:\n|$)))"
  var matches: array[5, string]
  var pos = start

  var firstLineSize = doc[pos ..< doc.len].matchLen(markerRegex, matches=matches)
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
    size = doc[pos ..< doc.len].matchLen(re(r"^(?:\s*| {" & fmt"{padding}" & r"}([^\n]*))(\n|$)"), matches=matches)
    if size != -1:
      listItemDoc &= matches[0]
      listItemDoc &= matches[1]
      if listItemDoc.startswith("\n") and matches[0] == "":
        pos += size
        break
    elif listItemDoc.find(re"\n{2,}$") == -1:
      size = doc[pos ..< doc.len].matchLen(re("^(" & LAZINESS_TEXT & ")"), matches=matches)
      if size != -1:
        listItemDoc &= matches[0]
      else:
          break
    else:
      break

    pos += size

  return pos - start

proc parseUnorderedListItem*(doc: string, start=0, marker: var string, listItemDoc: var string): int =
  #  thematic break takes precedence over list item.
  if doc[start ..< doc.len].matchLen(re(r"^" & THEMATIC_BREAK_RE)) != -1:
    return -1

  let markerRegex = re"^(?P<leading> {0,3})(?P<marker>[*\-+])(?: *$| *\n|(?<indent>(?: +|\t+))([^\n]+(?:\n|$)))"
  var matches: array[5, string]
  var pos = start

  var firstLineSize = doc[pos ..< doc.len].matchLen(markerRegex, matches=matches)
  if firstLineSize == -1:
    return -1

  pos += firstLineSize

  var leading = matches[0]
  if marker == "":
    marker = matches[1]
  if marker != matches[1]:
    return -1

  listItemDoc = matches[3]

  var indent = 1
  if matches[2].contains(re"\t"):
    indent = 1
    listItemDoc = " ".repeat(matches[2].len * 4 - 2) & listItemDoc
  elif matches[2].len > 1 and matches[2].len <= 4:
    indent = matches[2].len
  elif matches[2].len > 4: # code block indent is still 1.
    listItemDoc = matches[2][1 ..< matches[2].len] & listItemDoc

  var padding = marker.len + leading.len + indent

  var size = 0
  while pos < doc.len:
    size = doc[pos ..< doc.len].matchLen(re(r"^(?:[ \t]*| {" & fmt"{padding}" & r"}([^\n]*))(\n|$)"), matches=matches)
    if size != -1:
      listItemDoc &= matches[0]
      listItemDoc &= matches[1]
      if listItemDoc.startswith("\n") and matches[0] == "":
        pos += size
        break
    elif listItemDoc.find(re"\n{2,}$") == -1:
      size = doc[pos ..< doc.len].matchLen(re("^(" & LAZINESS_TEXT & ")"), matches=matches)
      if size != -1:
        listItemDoc &= matches[0]
      else:
          break
    else:
      break

    pos += size

  return pos - start

proc parseUnorderedList(doc: string, start: int): ParseResult =
  var pos = start
  var marker = ""
  var listItems: seq[Token]

  while pos < doc.len:
    var listItemDoc = ""
    var itemSize = parseUnorderedListItem(doc, pos, marker, listItemDoc)
    if itemSize == -1:
      break

    var listItem = Token(
      type: ListItemToken,
      doc: listItemDoc,
      listItemVal: ListItem(
        marker: marker
      )
    )
    listItems.add(listItem)

    pos += itemSize

  if marker == "":
    return (nil, -1)

  var ulToken = Token(
    type: UnorderedListToken,
    doc: doc[start ..< pos],
    ulVal: UnorderedList(
      loose: false
    )
  )
  for listItem in listItems:
    ulToken.children.append(listItem)

  return (token: ulToken, pos: pos)

proc parseOrderedList(doc: string, start: int): ParseResult =
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

    var listItem = Token(
      type: ListItemToken,
      doc: listItemDoc,
      listItemVal: ListItem(
        marker: marker
      )
    )
    listItems.add(listItem)

    pos += itemSize

  if marker == "":
    return (nil, -1)

  var olToken = Token(
    type: OrderedListToken,
    doc: doc[start ..< pos],
    olVal: OrderedList(
      start: startIndex,
      loose: false
    )
  )
  for listItem in listItems:
    olToken.children.append(listItem)

  return (token: olToken, pos: pos)

proc parseThematicBreak(doc: string, start: int): ParseResult =
  let size = doc.since(start).matchLen(re(r"^" & THEMATIC_BREAK_RE))
  if size == -1: return (nil, -1)
  return (
    token: Token(
      type: ThematicBreakToken,
      doc: doc.since(start, offset=size),
      hrVal: ""
    ),
    pos: start+size
  )

proc parseFencedCode*(doc: string, indent: var int, size: var int): string =
  var matches: array[2, string]
  size = doc.matchLen(re"((?: {0,3})?)(`{3,}|~{3,})", matches=matches)
  if size == -1:
    return ""
  indent = matches[0].len
  doc[0 ..< size].strip

proc parseCodeContent*(doc: string, indent: int, fence: string, codeContent: var string): int =
  var closeSize = -1
  var pos = 0
  var indentPrefix = ""
  codeContent = ""
  for i in (0 ..< indent):
    indentPrefix &= " "
  let closeRe = re(r"(?: {0,3})" & fence & fmt"{fence[0]}" & "{0,}(?:$|\n)")
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
  pos

proc parseCodeInfo*(doc: string, size: var int): string =
  var matches: array[1, string]
  size = doc.matchLen(re"(?: |\t)*([^`\n]*)?(?:\n|$)", matches=matches)
  if size == -1:
    return ""
  for item in matches[0].splitWhitespace:
    return item
  return ""

proc parseTildeBlockCodeInfo*(doc: string, size: var int): string =
  var matches: array[1, string]
  size = doc.matchLen(re"(?: |\t)*(.*)?(?:\n|$)", matches=matches)
  if size == -1:
    return ""
  for item in matches[0].splitWhitespace:
    return item
  return ""

proc parseFencedCode(doc: string, start: int): ParseResult =
  var pos = start
  var indent = 0

  var fenceSize = -1
  var fence = doc.since(start).parseFencedCode(indent, fenceSize)

  if fenceSize == -1: return (nil, -1)

  pos += fenceSize

  var infoSize = -1
  var info: string
  if fence.startsWith("`"):
    info = doc.since(pos).parseCodeInfo(infoSize)
  else:
    info = doc.since(pos).parseTildeBlockCodeInfo(infoSize)
  if infoSize == -1: return (nil, -1)

  pos += infoSize

  var codeContent = ""
  var codeContentSize = doc.since(pos).parseCodeContent(indent, fence, codeContent)
  pos += codeContentSize

  if doc.since(pos).matchLen(re"\n$") != -1:
    pos += 1

  let codeToken = Token(
    type: FencedCodeToken,
    doc: codeContent,
    fenceCodeVal: Fenced(info: info),
  )
  return (token: codeToken, pos: pos)


proc parseIndentedCode*(doc: string, start: int): ParseResult =
  let reIndentedCode = re"^(?: {4}| {0,3}\t)(.*\n?)"
  var size: int
  var code: string
  var matches: array[1, string]
  let firstLine = doc.since(start).firstLine
  if not firstLine.match(reIndentedCode, matches=matches): return (nil, -1)
  if matches[0].isBlank: return (nil, -1)
  size += firstLine.len
  code = matches[0]
  for line in doc.since(start).restLines:
    if line.isBlank:
      code &= line.replace(re"^ {0,4}", "")
      size += line.len
    elif line.match(reIndentedCode, matches=matches):
      code &= matches[0]
      size += line.len
    else:
      break
  let indentedCode = Token(
    type: IndentedCodeToken,
    doc: code,
    indentedCodeVal: "",
  )
  return (token: indentedCode, pos: start+size)

proc parseSetextHeadingContent*(doc: string, headingContent: var string, headingLevel: var int): int =
  var pos = 0
  var markerLen = 0
  var lineNumber = 0
  var matches: array[1, string]
  let pattern = re(r" {0,3}(=|-)+ *(?:\n+|$)")
  headingLevel = 0
  for line in doc.splitLines(keepEol=true):
    if lineNumber == 0:
      pos += line.len
      lineNumber += 1
      continue
    else:
      lineNumber += 1
    if line.match(re"^(?:\n|$)"): # empty line: break
      break
    if line.matchLen(re"^ {4,}") != -1: # not a code block anymore.
      pos += line.len
      continue
    if line.match(pattern, matches=matches):
      pos += line.len
      markerLen = line.len
      if matches[0] == "=":
        headingLevel = 1
      elif matches[0] == "-":
        headingLevel = 2
      break
    else:
      pos += line.len
  if headingLevel == 0:
    -1
  else:
    headingContent = doc[0 ..< pos - markerLen]
    pos


proc parseSetextHeading(doc: string, start: int): ParseResult =
  var content: string
  var level: int

  let size = doc.since(start).parseSetextHeadingContent(content, level)
  if size == -1: return (nil, -1)
  if content.match(re"(?:\s*\n)+"): return (nil, -1)

  return (
    token: Token(
      type: SetextHeadingToken,
      doc: content.strip,
      setextHeadingVal: Heading(
        level: level
      )
    ),
    pos: start+size
  )

const ATX_HEADING_RE* = r" {0,3}(#{1,6})([ \t]+)?(?(2)([^\n]*?))([ \t]+)?(?(4)#*) *(?:\n+|$)"

proc getAtxHeading*(s: string): tuple[level: int, doc: string, size: int] =
  var matches: array[4, string]
  let size = s.matchLen(
    re(r"^" & ATX_HEADING_RE),
    matches=matches
  )
  if size == -1:
    return (level: 0, doc: "", size: -1)

  let level = matches[0].len
  let doc = if matches[2] =~ re"#+": "" else: matches[2]
  return (level: level, doc: doc, size: size)

proc parseATXHeading(doc: string, start: int = 0): ParseResult =
  let res = doc.since(start).getAtxHeading()
  if res.size == -1: return (nil, -1)
  return (
    token: Token(
      type: ATXHeadingToken,
      doc: res.doc,
      atxHeadingVal: Heading(
        level: res.level
      )
    ),
    pos: start+res.size
  )

proc parseBlankLine*(doc: string, start: int): ParseResult =
  let size = doc.since(start).matchLen(re(r"^((?:\s*\n)+)"))
  if size == -1: return (nil, -1)
  return (
    token: Token(
      type: BlankLineToken,
      doc: doc.since(start, offset=size),
      blankLineVal: doc.since(start, offset=size)
    ),
    pos: start+size
  )

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
      result.add(doc[lastPos ..< pos])
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

  result.add(doc[lastPos ..< max])

proc parseTableAligns*(doc: string, aligns: var seq[string]): bool =
  if not doc.match(re"^ {0,3}[-:|][-:|\s]*(?:\n|$)"):
    return false
  var columns = doc.split("|")
  for index, column in columns:
    var t = column.strip
    if t == "":
      if index == 0 or index == columns.len - 1:
        continue
      else:
        return false
    if not t.match(re"^:?-+:?$"):
      return false
    if t[0] == ':':
      if t[t.len - 1] == ':':
        aligns.add("center")
      else:
        aligns.add("left")
    elif t[t.len - 1] == ':':
      aligns.add("right")
    else:
      aligns.add("")
  true

proc parseHTMLTable(doc: string, start: int): ParseResult =
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
  let lines = doc.since(start).splitLines(keepEol=true)
  if lines.len < 2:
    return (nil, -1)

  var aligns: seq[string]
  if not parseTableAligns(lines[1], aligns):
    return (nil, -1)

  if lines[0].matchLen(re"^ {4,}") != -1:
    return (nil, -1)

  if lines[0] == "" or lines[0].find('|') == -1:
    return (nil, -1)

  var heads = parseTableRow(lines[0].replace(re"^\||\|$", ""))
  if heads.len > aligns.len:
    return (nil, -1)

  var theadToken = Token(
    type: THeadToken,
    doc: lines[0],
    theadVal: HTMLTableHead(size: 1)
  )
  var theadRowToken = Token(
    type: TableRowToken,
    doc: lines[0],
    tableRowVal: HTMLTableRow(th: true, td: false),
  )
  for index, elem in heads:
    var thToken = Token(
      type: THeadCellToken,
      doc: elem.strip,
      theadCellVal: HTMLTableCell(
        i: index,
        j: 0,
        align: aligns[index],
      )
    )
    theadRowToken.children.append(thToken)
  theadToken.children.append(theadRowToken)

  pos += lines[0].len + lines[1].len

  var tbodyRows: seq[Token]
  for lineIndex, line in lines[2 ..< lines.len]:
    if line.matchLen(re"^ {4,}") != -1:
      break
    if line == "" or line.find('|') == -1:
      break

    var rowColumns = parseTableRow(line.replace(re"^\||\|$", ""))

    var tableRowToken = Token(
      type: TableRowToken,
      doc: "",
      tableRowVal: HTMLTableRow(th: false, td: true),
    )
    for index, elem in heads:
      var doc = 
        if index >= rowColumns.len:
          ""
        else:
          rowColumns[index]
      var tdToken = Token(
        type: TBodyCellToken,
        doc: doc.replace(re"\\\|", "|").strip,
        tbodyCellVal: HTMLTableCell(
          i: index,
          j: lineIndex,
          align: aligns[index]
        )
      )
      tableRowToken.children.append(tdToken)
    tbodyRows.add(tableRowToken)
    pos += line.len

  var tableToken = Token(
    type: TableToken,
    doc: doc[start ..< pos],
    tableVal: HTMLTable(
      aligns: aligns,
    )
  )
  tableToken.children.append(theadToken)
  if tbodyRows.len > 0:
    var tbodyToken = Token(
      type: TBodyToken,
      doc: doc[start+lines[0].len+lines[1].len ..< pos],
      tbodyVal: HTMLTableBody(size: tbodyRows.len)
    )
    for tbodyRowToken in tbodyRows:
      tbodyToken.children.append(tbodyRowToken)
    tableToken.children.append(tbodyToken)
  return (token: tableToken, pos: pos)

proc parseHTMLBlockContent*(doc: string, startPattern: string, endPattern: string, html: var string, ignoreCase = false): int =
  # Algorithm:
  # firstLine: detectOpenTag
  # fail fast.
  # firstLine: detectCloseTag
  # success fast.
  # rest of the lines:
  #   detectCloseTag
  #   success fast.
  let startRe =
    if ignoreCase:
      re(startPattern, {RegexFlag.reIgnoreCase})
    else:
      re(startPattern)
  let endRe =
    if ignoreCase:
      re(endPattern, {RegexFlag.reIgnoreCase})
    else:
      re(endPattern)
  var pos = 0
  var size = -1
  let docLines = doc.splitLines(keepEol=true)
  if docLines.len == 0:
    return -1
  let firstLine = docLines[0]
  size = firstLine.matchLen(startRe)
  if size == -1:
    return -1
  html = firstLine
  size = firstLine.find(endRe)
  if size != -1:
    return firstLine.len
  else:
    pos = firstLine.len
  for line in docLines[1 ..< docLines.len]:
    pos += line.len
    html &= line
    if line.find(endRe) != -1:
      break
  return pos

proc parseHTMLBlock(doc: string, start: int): ParseResult =
  var htmlContent: string
  var size: int

  size = doc.since(start).parseHTMLBlockContent(
    HTML_SCRIPT_START, HTML_SCRIPT_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  size = doc.since(start).parseHTMLBlockContent(
    HTML_COMMENT_START, HTML_COMMENT_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  size = doc.since(start).parseHTMLBlockContent(
    HTML_PROCESSING_INSTRUCTION_START, HTML_PROCESSING_INSTRUCTION_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  size = doc.since(start).parseHTMLBlockContent(
    HTML_DECLARATION_START, HTML_DECLARATION_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  size = doc.since(start).parseHTMLBlockContent(
    HTML_CDATA_START, HTML_CDATA_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  size = doc.since(start).parseHTMLBlockContent(
    HTML_TAG_START, HTML_TAG_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  size = doc.since(start).parseHTMLBlockContent(
    HTML_OPEN_CLOSE_TAG_START, HTML_OPEN_CLOSE_TAG_END, htmlContent)
  if size != -1:
    return (
      token: Token(
        type: HTMLBlockToken,
        doc: htmlContent,
        htmlBlockVal: ""
      ),
      pos: start+size
    )

  return (nil, -1)


proc parseBlockquote(doc: string, start: int): ParseResult =
  let markerContent = re(r"^(( {0,3}>([^\n]*(?:\n|$)))+)")
  var matches: array[3, string]
  var pos = start
  var size = -1
  var document = ""
  var found = false

  while pos < doc.len:
    size = doc.since(pos).matchLen(markerContent, matches=matches)

    if size == -1:
      break

    found = true
    pos += size
    # extract content with blockquote mark
    document &= matches[0].replacef(re"(^|\n) {0,3}> ?", "$1")

    # blank line in non-lazy content always breaks the blockquote.
    if matches[2].strip == "":
      document = document.strip(leading=false, trailing=true)
      break

    # find the empty line in lazy content
    if doc[start ..< pos].find(re" {4,}[^\n]+\n") != -1 and doc.since(pos).matchLen(re"^\n|^ {4,}|$") > -1:
      break

    # find the laziness text
    size = doc.since(pos).matchLen(re("^(" & LAZINESS_TEXT & ")"), matches=matches)

    # blank line in laziness text always breaks the blockquote
    if size == -1:
      break

    # concat the laziness text
    pos += size
    document &= matches[0]

  if not found:
    return (nil, -1)

  let blockquote = Token(
    type: BlockquoteToken,
    doc: document,
    blockquoteVal: Blockquote(
      doc: document
    )
  )
  return (token: blockquote, pos: pos)

proc parseReference*(doc: string, start: int): ParseResult =
  var pos = start

  var markStart = doc.since(pos).matchLen(re"^ {0,3}\[")
  if markStart == -1:
    return (nil, -1)

  pos += markStart - 1

  var label: string
  var labelSize = getLinkLabel(doc, pos, label)

  # Link should have matching ] for [.
  if labelSize == -1:
    return (nil, -1)

  # A link label must contain at least one non-whitespace character.
  if label.find(re"\S") == -1:
    return (nil, -1)

  # An inline link consists of a link text followed immediately by a left parenthesis (
  pos += labelSize # [link]

  if pos >= doc.len or doc[pos] != ':':
    return (nil, -1)
  pos += 1

  # parse whitespace
  var whitespaceLen = doc.since(pos).matchLen(re"^[ \t]*\n?[ \t]*")
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse destination
  var destinationSlice: Slice[int]
  var destinationLen = getLinkDestination(doc, pos, destinationslice)

  if destinationLen <= 0:
    return (nil, -1)

  pos += destinationLen

  # parse whitespace
  var whitespaces: array[1, string]
  whitespaceLen = doc.since(pos).matchLen(re"^([ \t]*\n?[ \t]*)", matches=whitespaces)
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse title (optional)
  var titleSlice: Slice[int]
  var titleLen = 0
  if pos<doc.len and (doc[pos] == '(' or doc[pos] == '\'' or doc[pos] == '"'):
    # at least one whitespace before the optional title.
    if not {' ', '\t', '\n'}.contains(doc[pos-1]):
      return (nil, -1)

    titleLen = getLinkTitle(doc, pos, titleSlice)
    if titleLen >= 0:
      pos += titleLen
      # link title may not contain a blank line
      if doc[titleSlice].find(re"\n{2,}") != -1:
        return (nil, -1)

    # parse whitespace, no more non-whitespace is allowed from now.
    whitespaceLen = doc[pos ..< doc.len].matchLen(re"^\s*(?:\n|$)")
    if whitespaceLen != -1:
      pos += whitespaceLen
    # title might have trailing characters, but the label and dest is already enough.
    # [foo]: /url
    # "title" ok
    elif whitespaces[0].contains("\n"):
      pos -= titleLen
      titleLen = -1
    else:
      return (nil, -1)

  # construct token
  var title = ""
  if titleLen > 0:
    title = doc[titleSlice]

  var url = doc[destinationSlice]

  var reference = Token(
    type: ReferenceToken,
    doc: doc[start ..< pos],
    referenceVal: Reference(
      text: label,
      url: url,
      title: title,
    )
  )
  return (token: reference, pos: pos)


proc isContainerBlock(tokenType: TokenType): bool =
  return {
    OrderedListToken,
    UnorderedListToken,
    BlockquoteToken,
  }.contains(tokenType)

proc parseBlock(state: State, token: Token) =
  let doc = token.doc
  var pos = 0
  var res: ParseResult
  while pos < doc.len:
    for rule in state.ruleSet.blockRules:
      case rule
      of UnorderedListToken:
        res = parseUnorderedList(doc, pos)
        if res.pos != -1:
          for listItem in res.token.children.items:
            if listItem.doc != "":
              parseBlock(state, listItem)
          res.token.ulVal.loose = res.token.parseLoose
          for listItem in res.token.children.items:
            listItem.listItemVal.loose = res.token.ulVal.loose
      of OrderedListToken:
        res = parseOrderedList(doc, pos)
        if res.pos != -1:
          for listItem in res.token.children.items:
            if listItem.doc != "":
              parseBlock(state, listItem)
          res.token.olVal.loose = res.token.parseLoose
          for listItem in res.token.children.items:
            listItem.listItemVal.loose = res.token.olVal.loose
      of ReferenceToken:
        res = parseReference(doc, pos)
        if res.pos != -1 and not state.references.contains(res.token.referenceVal.text):
          state.references[res.token.referenceVal.text] = res.token.referenceVal
      of BlockquoteToken:
        res = parseBlockquote(doc, pos)
        if res.pos != -1 and res.token.doc.strip != "":
          parseBlock(state, res.token)
      of TableToken: res = parseHTMLTable(doc, pos)
      of FencedCodeToken: res = parseFencedCode(doc, pos)
      of IndentedCodeToken: res = parseIndentedCode(doc, pos)
      of HTMLBlockToken: res = parseHTMLBlock(doc, pos)
      of SetextHeadingToken: res = parseSetextHeading(doc, pos)
      of BlankLineToken: res = parseBlankLine(doc, pos)
      of ThematicBreakToken: res = parseThematicBreak(doc, pos)
      of ATXHeadingToken: res = parseATXHeading(doc, pos)
      of ParagraphToken: res = parseParagraph(doc, pos)
      else: raise newException(MarkdownError, fmt"unknown rule.")

      if res.pos != -1:
        pos = res.pos
        token.children.append(res.token)
        break

    if pos == -1:
      raise newException(MarkdownError, fmt"unknown rule.")

proc parseText(state: State, token: Token, start: int): int =
  var text = Token(
    type: TextToken,
    textVal: token.doc[start ..< start+1],
  )
  token.children.append(text)
  result = 1 # FIXME: should match aggresively.

proc parseSoftLineBreak(state: State, token: Token, start: int): int =
  result = token.doc[start ..< token.doc.len].matchLen(re"^ \n *")
  if result != -1:
    token.children.append(Token(
      type: SoftLineBreakToken,
      softLineBreakVal: "\n"
    ))

proc parseAutoLink(state: State, token: Token, start: int): int =
  if token.doc[start] != '<':
    return -1

  let EMAIL_RE = r"^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>"
  var emailMatches: array[1, string]
  result = token.doc[start ..< token.doc.len].matchLen(re(EMAIL_RE, {RegexFlag.reIgnoreCase}), matches=emailMatches)

  if result != -1:
    var url = emailMatches[0]
    # TODO: validate and normalize the link
    token.children.append(Token(
      type: AutoLinkToken,
      autoLinkVal: AutoLink(
        text: url,
        url: fmt"mailto:{url}"
      )
    ))
    return result
  
  let LINK_RE = r"^<([a-zA-Z][a-zA-Z0-9+.\-]{1,31}):([^<>\x00-\x20]*)>"
  var linkMatches: array[2, string]
  result = token.doc[start ..< token.doc.len].matchLen(re(LINK_RE, {RegexFlag.reIgnoreCase}), matches=linkMatches)

  if result != -1:
    var schema = linkMatches[0]
    var uri = linkMatches[1]
    token.children.append(Token(
      type: AutoLinkToken,
      autoLinkVal: AutoLink(
        text: fmt"{schema}:{uri}",
        url: fmt"{schema}:{uri}",
      )
    ))
    return result

proc scanInlineDelimiters*(doc: string, start: int, delimeter: var Delimiter) =
  var charBefore = '\n'
  var charAfter = '\n'
  let charCurrent = doc[start]
  var isCharAfterWhitespace = true
  var isCharBeforeWhitespace = true

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
    isCharBeforeWhitespace = fmt"{charBefore}".match(re"^\s") or doc.runeAt(start - 1).isWhitespace

  # get the character after the delimeter runs
  if start + delimeter.num + 1 < doc.len:
    charAfter = doc[start + delimeter.num]
    isCharAfterWhitespace = fmt"{charAfter}".match(re"^\s") or doc.runeAt(start + delimeter.num).isWhitespace

  let isCharAfterPunctuation = fmt"{charAfter}".match(re"^\p{P}")
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

proc parseDelimiter(state: State, token: Token, start: int, delimeters: var DoublyLinkedList[Delimiter]): int =
  if token.doc[start] != '*' and token.doc[start] != '_':
    return -1

  var delimeter = Delimiter(
    token: nil,
    kind: fmt"{token.doc[start]}",
    num: 0,
    originalNum: 0,
    isActive: true,
    canOpen: false,
    canClose: false,
  )

  scanInlineDelimiters(token.doc, start, delimeter)
  if delimeter.num == 0:
    return -1

  result = delimeter.num

  var textToken = Token(
    type: TextToken,
    textVal: token.doc[start ..< start+result]
  )
  token.children.append(textToken)
  delimeter.token = textToken
  delimeters.append(delimeter)

proc getLinkDestination*(doc: string, start: int, slice: var Slice[int]): int =
  # if start < 1 or doc[start - 1] != '(':
  #   raise newException(MarkdownError, fmt"{start} can not be the start of inline link destination.")

  # A link destination can be 
  # a sequence of zero or more characters between an opening < and a closing >
  # that contains no line breaks or unescaped < or > characters, or
  if doc[start] == '<':
    result = doc[start ..< doc.len].matchLen(re"^<([^\n<>\\]*)>")
    if result != -1:
      slice.a = start + 1
      slice.b = start + result - 2
    return result

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
  for i, ch in doc[start ..< doc.len]:
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
    return -1
  if urlLen == -1:
     return -1
  slice = (start ..< start+urlLen)
  return urlLen

proc getLinkTitle*(doc: string, start: int, slice: var Slice[int]): int =
  var marker = doc[start]
  # Titles may be in single quotes, double quotes, or parentheses
  if marker != '"' and marker != '\'' and marker != '(':
    return -1
  if marker == '(':
    marker = ')'
  var isEscaping = false
  for i, ch in doc[start+1 ..< doc.len]:
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true
      continue
    elif ch == marker:
      slice = (start+1 .. start+i)
      return i+2
  return -1

proc normalizeLabel*(label: string): string =
  # One label matches another just in case their normalized forms are equal.
  # To normalize a label, strip off the opening and closing brackets,
  # perform the Unicode case fold, strip leading and trailing whitespace
  # and collapse consecutive internal whitespace to a single space.
  label.toLower.strip.replace(re"\s+", " ")

proc getLinkLabel*(doc: string, start: int, label: var string): int =
  if doc[start] != '[':
    raise newException(MarkdownError, fmt"{doc[start]} cannot be the start of link label.")

  if start+1 >= doc.len:
    return -1

  var isEscaping = false
  var size = 0
  for i, ch in doc[start+1 ..< doc.len]:
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
      return -1

    # A link label can have at most 999 characters inside the square brackets.
    if size > 999:
      return -1

  label = doc[start+1 ..< start+size].normalizeLabel
  return size + 1


proc getLinkText*(doc: string, start: int, slice: var Slice[int], allowNested: bool = false): int =
  # based on assumption: token.doc[start] = '['
  if doc[start] != '[':
    raise newException(MarkdownError, fmt"{start} is not [.")

  # A link text consists of a sequence of zero or more inline elements enclosed by square brackets ([ and ]).
  var level = 0
  var isEscaping = false
  var skip = 0
  for i, ch in doc[start ..< doc.len]:
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
      skip = doc[start+i ..< doc.len].matchLen(re"^((`+)\s*([\s\S]*?[^`])\s*\2(?!`))") - 1

    # autolinks, and raw HTML tags bind more tightly than the brackets in link text.
    elif ch == '<':
      skip = doc[start+i ..< doc.len].matchLen(re"^<[^>]*>") - 1

    # Links may not contain other links, at any level of nesting.
    # Image description may contain links.
    if level == 0 and not allowNested and doc[start .. start+i].find(re"[^!]\[[^]]*\]\([^)]*\)") > -1:
        return -1
    if level == 0 and not allowNested and doc[start .. start+i].find(re"[^!]\[[^]]*\]\[[^]]*\]") > -1:
        return -1

    if level == 0:
      slice = (start .. start+i)
      return i+1

  return -1


proc parseInlineLink(state: State, token: Token, start: int, labelSlice: Slice[int]): int =
  if token.doc[start] != '[':
    return -1

  var pos = labelSlice.b + 2 # [link](

  # parse whitespace
  var whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t\n]*")
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse destination
  var destinationSlice: Slice[int]
  var destinationLen = getLinkDestination(token.doc, pos, destinationslice)

  if destinationLen == -1:
    return -1

  pos += destinationLen

  # parse whitespace
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[\x{0020}\x{0009}\x{000A}\x{000B}\x{000C}\x{000D}]*")
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse title (optional)
  if token.doc[pos] != '(' and token.doc[pos] != '\'' and token.doc[pos] != '"' and token.doc[pos] != ')':
    return -1
  var titleSlice: Slice[int]
  var titleLen = getLinkTitle(token.doc, pos, titleSlice)

  if titleLen >= 0:
    pos += titleLen

  # parse whitespace
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # require )
  if pos >= token.doc.len:
    return -1
  if token.doc[pos] != ')':
    return -1

  # construct token
  var title = ""
  if titleLen >= 0:
    title = token.doc[titleSlice]
  var url = token.doc[destinationSlice]
  var text = token.doc[labelSlice.a+1 ..< labelSlice.b]
  var link = Token(
    type: LinkToken,
    doc: token.doc[start .. pos],
    linkVal: Link(
      text: text,
      url: url,
      title: title,
    )
  )
  parseLinkInlines(state, link)
  token.children.append(link)
  result = pos - start + 1

proc parseFullReferenceLink(state: State, token: Token, start: int, textSlice: Slice[int]): int =
  var pos = textSlice.b + 1
  var label: string
  var labelSize = getLinkLabel(token.doc, pos, label)

  if labelSize == -1:
    return -1

  if not state.references.contains(label):
    return -1

  pos += labelSize

  var text = token.doc[textSlice.a+1 ..< textSlice.b]
  var reference = state.references[label]
  var link = Token(
    type: LinkToken,
    doc: token.doc[start ..< pos],
    linkVal: Link(
      url: reference.url,
      title: reference.title,
      text: text
    )
  )
  parseLinkInlines(state, link)
  token.children.append(link)
  return pos - start

proc parseCollapsedReferenceLink(state: State, token: Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var text = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var link = Token(
    type: LinkToken,
    doc: token.doc[start ..< label.b+1],
    linkVal: Link(
      url: reference.url,
      title: reference.title,
      text: text
    )
  )
  parseLinkInlines(state, link)
  token.children.append(link)
  return label.b - start + 3

proc parseShortcutReferenceLink(state: State, token: Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var text = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var link = Token(
    type: LinkToken,
    doc: token.doc[start ..< label.b+1],
    linkVal: Link(
      url: reference.url,
      title: reference.title,
      text: text
    )
  )
  parseLinkInlines(state, link)
  token.children.append(link)
  return label.b - start + 1


proc parseLink*(state: State, token: Token, start: int): int =
  # Link should start with [
  if token.doc[start] != '[':
    return -1

  var labelSlice: Slice[int]
  result = getLinkText(token.doc, start, labelSlice)
  # Link should have matching ] for [.
  if result == -1:
    return -1

  # An inline link consists of a link text followed immediately by a left parenthesis (
  if labelSlice.b + 1 < token.doc.len and token.doc[labelSlice.b + 1] == '(':
    var size = parseInlineLink(state, token, start, labelSlice)
    if size != -1:
      return size

  # A collapsed reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document, followed by the string []. 
  if labelSlice.b + 2 < token.doc.len and token.doc[labelSlice.b+1 .. labelSlice.b+2] == "[]":
    var size = parseCollapsedReferenceLink(state, token, start, labelSlice)
    if size != -1:
      return size

  # A full reference link consists of a link text immediately followed by a link label 
  # that matches a link reference definition elsewhere in the document.
  elif labelSlice.b + 1 < token.doc.len and token.doc[labelSlice.b + 1] == '[':
    return parseFullReferenceLink(state, token, start, labelSlice)

  # A shortcut reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document and is not followed by [] or a link label.
  return parseShortcutReferenceLink(state, token, start, labelSlice)

proc parseInlineImage(state: State, token: Token, start: int, labelSlice: Slice[int]): int =
  var pos = labelSlice.b + 2 # ![link](

  # parse whitespace
  var whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # parse destination
  var destinationSlice: Slice[int]
  var destinationLen = getLinkDestination(token.doc, pos, destinationslice)
  if destinationLen == -1:
    return -1

  pos += destinationLen

  # parse whitespace
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # parse title (optional)
  if token.doc[pos] != '(' and token.doc[pos] != '\'' and token.doc[pos] != '"' and token.doc[pos] != ')':
    return -1
  var titleSlice: Slice[int]
  var titleLen = getLinkTitle(token.doc, pos, titleSlice)

  if titleLen >= 0:
    pos += titleLen

  # parse whitespace
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # require )
  if pos >= token.doc.len:
    return -1
  if token.doc[pos] != ')':
    return -1

  # construct token
  var title = ""
  if titleLen >= 0:
    title = token.doc[titleSlice]
  var url = token.doc[destinationSlice]
  var text = token.doc[labelSlice.a+1 ..< labelSlice.b]

  var image = Token(
    type: ImageToken,
    doc: token.doc[start-1 ..< pos+1],
    imageVal: Image(
      alt: text,
      url: url,
      title: title,
    )
  )

  parseLinkInlines(state, image, allowNested=true)
  token.children.append(image)
  result = pos - start + 2

proc parseFullReferenceImage(state: State, token: Token, start: int, altSlice: Slice[int]): int =
  var pos = altSlice.b + 1
  var label: string
  var labelSize = getLinkLabel(token.doc, pos, label)

  if labelSize == -1:
    return -1

  pos += labelSize

  var alt = token.doc[altSlice.a+1 ..< altSlice.b]
  if not state.references.contains(label):
    return -1

  var reference = state.references[label]
  var image = Token(
    type: ImageToken,
    doc: token.doc[start ..< pos-1],
    imageVal: Image(
      url: reference.url,
      title: reference.title,
      alt: alt
    )
  )
  parseLinkInlines(state, image, allowNested=true)
  token.children.append(image)
  return pos - start + 1

proc parseCollapsedReferenceImage(state: State, token: Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var alt = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var image = Token(
    type: ImageToken,
    doc: token.doc[start ..< label.b+2],
    imageVal: Image(
      url: reference.url,
      title: reference.title,
      alt: alt
    )
  )
  parseLinkInlines(state, image)
  token.children.append(image)
  return label.b - start + 3

proc parseShortcutReferenceImage(state: State, token: Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var alt = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var image = Token(
    type: ImageToken,
    doc: token.doc[start ..< label.b+1],
    imageVal: Image(
      url: reference.url,
      title: reference.title,
      alt: alt
    )
  )
  parseLinkInlines(state, image)
  token.children.append(image)
  return label.b - start + 1


proc parseImage*(state: State, token: Token, start: int): int =
  # Image should start with ![
  if not token.doc[start ..< token.doc.len].match(re"^!\["):
    return -1

  var labelSlice: Slice[int]
  var labelSize = getLinkText(token.doc, start+1, labelSlice, allowNested=true)

  # Image should have matching ] for [.
  if labelSize == -1:
    return -1

  # An inline image consists of a link text followed immediately by a left parenthesis (
  if labelSlice.b + 1 < token.doc.len and token.doc[labelSlice.b + 1] == '(':
    return parseInlineImage(state, token, start+1, labelSlice)

  # A collapsed reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document, followed by the string []. 
  elif labelSlice.b + 2 < token.doc.len and token.doc[labelSlice.b+1 .. labelSlice.b+2] == "[]":
    return parseCollapsedReferenceImage(state, token, start, labelSlice)

  # A full reference link consists of a link text immediately followed by a link label 
  # that matches a link reference definition elsewhere in the document.
  if labelSlice.b + 1 < token.doc.len and token.doc[labelSlice.b + 1] == '[':
    return parseFullReferenceImage(state, token, start, labelSlice)

  # A shortcut reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document and is not followed by [] or a link label.
  else:
    return parseShortcutReferenceImage(state, token, start, labelSlice)

const ENTITY = r"&(?:#x[a-f0-9]{1,6}|#[0-9]{1,7}|[a-z][a-z0-9]{1,31});"
proc parseHTMLEntity*(state: State, token: Token, start: int): int =
  if token.doc[start] != '&':
    return -1

  let regex = re(r"^(" & ENTITY & ")", {RegexFlag.reIgnoreCase})
  var matches: array[1, string]

  var size = token.doc[start .. token.doc.len - 1].matchLen(regex, matches)
  if size == -1:
    return -1

  var entity: string
  if matches[0] == "&#0;":
    entity = "\uFFFD"
  else:
    entity = escapeHTMLEntity(matches[0])

  token.children.append(Token(
    type: HTMLEntityToken,
    htmlEntityVal: entity
  ))
  return size

proc parseEscape*(state: State, token: Token, start: int): int =
  if token.doc[start] != '\\':
    return -1

  let regex = re"^\\([\\`*{}\[\]()#+\-.!_<>~|""$%&',/:;=?@^])"
  let size = token.doc[start ..< token.doc.len].matchLen(regex)
  if size == -1:
    return -1

  token.children.append(Token(
    type: EscapeToken,
    escapeVal: fmt"{token.doc[start+1]}"
  ))
  return 2

proc parseInlineHTML*(state: State, token: Token, start: int): int =
  if token.doc[start] != '<':
    return -1
  let regex = re("^(" & HTML_TAG & ")", {RegexFlag.reIgnoreCase})
  var matches: array[5, string]
  var size = token.doc[start ..< token.doc.len].matchLen(regex, matches=matches)

  if size == -1:
    return -1

  token.children.append(Token(
    type: InlineHTMLToken,
    inlineHTMLVal: matches[0]
  ))
  return size

proc parseHardLineBreak*(state: State, token: Token, start: int): int =
  if token.doc[start] != ' ' and token.doc[start] != '\\':
    return -1

  let size = token.doc[start ..< token.doc.len].matchLen(re"^((?: {2,}\n|\\\n)\s*)")

  if size == -1:
    return -1

  token.children.append(Token(
    type: HardLineBreakToken,
    hardLineBreakVal: ""
  ))
  return size

proc parseCodeSpan*(state: State, token: Token, start: int): int =
  if token.doc[start] != '`':
    return -1

  var matches: array[5, string]
  var size = token.doc[start ..< token.doc.len].matchLen(re"^((`+)([^`]|[^`][\s\S]*?[^`])\2(?!`))", matches=matches)

  if size == -1:
    size = token.doc[start ..< token.doc.len].matchLen(re"^`+(?!`)")
    if size == -1:
      return -1
    token.children.append(Token(
      type: TextToken,
      textVal: token.doc[start ..< start+size]
    ))
    return size

  var codeSpanVal = matches[2].strip(chars={'\n'}).replace(re"[\n]+", " ")
  if codeSpanVal[0] == ' ' and codeSpanVal[codeSpanVal.len-1] == ' ' and not codeSpanVal.match(re"^[ ]+$"):
    codeSpanVal = codeSpanVal[1 ..< codeSpanVal.len-1]

  token.children.append(Token(
    type: CodeSpanToken,
    codeSpanVal: codeSpanVal,
  ))
  return size

proc parseStrikethrough*(state: State, token: Token, start: int): int =
  if token.doc[start] != '~':
    return -1

  var matches: array[5, string]
  var size = token.doc[start ..< token.doc.len].matchLen(re"^(~~(?=\S)([\s\S]*?\S)~~)", matches=matches)

  if size == -1:
    return -1

  token.children.append(Token(
    type: StrikethroughToken,
    strikethroughVal: matches[1]
  ))
  return size

proc findInlineToken(state: State, token: Token, rule: TokenType, start: int, delimeters: var DoublyLinkedList[Delimiter]): int =
  case rule
  of EmphasisToken: result = parseDelimiter(state, token, start, delimeters)
  of AutoLinkToken: result = parseAutoLink(state, token, start)
  of LinkToken: result = parseLink(state, token, start)
  of ImageToken: result = parseImage(state, token, start)
  of HTMLEntityToken: result = parseHTMLEntity(state, token, start)
  of InlineHTMLToken: result = parseInlineHTML(state, token, start)
  of EscapeToken: result = parseEscape(state, token, start)
  of CodeSpanToken: result = parseCodeSpan(state, token, start)
  of StrikethroughToken: result = parseStrikethrough(state, token, start)
  of HardLineBreakToken: result = parseHardLineBreak(state, token, start)
  of SoftLineBreakToken: result = parseSoftLineBreak(state, token, start)
  of TextToken: result = parseText(state, token, start)
  else: raise newException(MarkdownError, fmt"{token.type} has no inline rule.")


proc removeDelimiter*(delimeter: var DoublyLinkedNode[Delimiter]) =
  if delimeter.prev != nil:
    delimeter.prev.next = delimeter.next
  if delimeter.next != nil:
    delimeter.next.prev = delimeter.prev
  delimeter = delimeter.next

proc processEmphasis*(state: State, token: Token, delimeterStack: var DoublyLinkedList[Delimiter]) =
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
  closer = delimeterStack.head
  # move forward, looking for closers, and handling each
  while closer != nil:
    # find the first closing delimeter.
    #
    # sometimes, the delimeter **can _not** close.
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
      openerInlineText.textVal = openerInlineText.textVal[0 .. ^(useDelims+1)]
      closerInlineText.textVal = closerInlineText.textVal[0 .. ^(useDelims+1)]

      # build contents for new emph element
      # add emph element to tokens
      var emToken: Token
      if useDelims == 2:
        emToken = Token(type: StrongToken)
      else:
        emToken = Token(type: EmphasisToken)

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
  while delimeterStack.head != nil:
    removeDelimiter(delimeterStack.head)

proc parseLinkInlines*(state: State, token: Token, allowNested: bool = false) =
  var delimeters: DoublyLinkedList[Delimiter]
  var pos = 0
  var size = 0
  if token.type == LinkToken:
    pos = 1
    size = token.linkVal.text.len - 1
  elif token.type == ImageToken:
    pos = 2
    size = token.imageVal.alt.len
  else:
    raise newException(MarkdownError, fmt"{token.type} has no link inlines.")

  for index, ch in token.doc[pos .. pos+size]:
    if 1+index < pos:
      continue
    var size = -1
    for rule in state.ruleSet.inlineRules:
      if not allowNested and rule == LinkToken:
        continue
      size = findInlineToken(state, token, rule, pos, delimeters)
      if size != -1:
        pos += size
        break
    if size == -1:
      token.children.append(Token(type: TextToken, textVal: fmt"{ch}"))
      pos += 1

  processEmphasis(state, token, delimeters)

proc parseLeafBlockInlines(state: State, token: Token) =
  var pos = 0
  var delimeters: DoublyLinkedList[Delimiter]

  for index, ch in token.doc[0 ..< token.doc.len].strip:
    if index < pos:
      continue
    var size = -1
    for rule in state.ruleSet.inlineRules:
      if token.type == rule:
        continue
      size = findInlineToken(state, token, rule, pos, delimeters)
      if size != -1:
        pos += size
        break
    if size == -1:
      token.children.append(Token(type: TextToken, textVal: fmt"{ch}"))
      pos += 1

  processEmphasis(state, token, delimeters)

proc isContainerToken(token: Token): bool =
  {DocumentToken, BlockquoteToken, ListItemToken, UnorderedListToken,
   OrderedListToken, TableToken, THeadToken, TBodyToken, TableRowToken, }.contains(token.type)

proc parseInline(state: State, token: Token) =
  if isContainerToken(token):
    for childToken in token.children.mitems:
      parseInline(state, childToken)
  else:
    parseLeafBlockInlines(state, token)

proc postProcessing(state: State, token: Token) =
  discard

proc parse(state: State, token: Token) =
  preProcessing(state, token)
  parseBlock(state, token)
  parseInline(state, token)
  postProcessing(state, token)

proc toSeq(tokens: DoublyLinkedList[Token]): seq[Token] =
  result = newSeq[Token]()
  for token in tokens.items:
    result.add(token)

proc renderToken(state: State, token: Token): string;
proc renderInline(state: State, token: Token): string =
  var s = state
  token.children.toSeq.map(
    proc(x: Token): string =
      result = s.renderToken(x)
  ).join("")

proc renderImageAlt*(state: State, token: Token): string =
  var s = state
  token.children.toSeq.map(
    proc(x: Token): string =
      case x.type
      of LinkToken: x.linkVal.text
      of ImageToken: x.imageVal.alt
      of EmphasisToken: s.renderInline(x)
      of StrongToken: s.renderInline(x)
      else: s.renderToken(x)
  ).join("")

proc renderParagraph(state: State, token: Token): string =
  if token.children.head == nil: ""
  else: p(state.renderInline(token))

proc renderListItemTightParagraph(state: State, token: Token): string =
  state.renderInline(token)

proc renderListItemChildren(state: State, token: Token): string =
  var html: string

  for child_node in token.children.nodes:
    var child_token = child_node.value
    if child_token.type == ParagraphToken and not token.listItemVal.loose:
      if child_node.prev != nil:
        result &= "\n"
      result &= state.renderListItemTightParagraph(child_token)
      if child_node.next == nil:
        return result
    else:
      html = renderToken(state, child_token)
      if html != "":
        result &= "\n"
        result &= html
  if token.listItemVal.loose or token.children.tail != nil:
    result &= "\n"

proc renderUnorderedList(state: State, token: Token): string =
  ul("\n", state.render(token))

proc renderOrderedList(state: State, token: Token): string =
  if token.olVal.start != 1:
    result = ol(start=fmt"{token.olVal.start}", "\n", state.render(token))
  else:
    result = ol("\n", state.render(token))

proc renderListItem(state: State, token: Token): string =
  let originalLoose = state.loose
  state.loose = token.listItemVal.loose
  result = li(state.renderListItemChildren(token))
  state.loose = originalLoose

proc renderTableHeadCell(state: State, token: Token): string =
  let align = token.theadCellVal.align
  if align == "":
    fmt"<th>{state.renderInline(token)}</th>"
  else:
    fmt("<th align=\"{align}\">{state.renderInline(token)}</th>")

proc renderTableBodyCell(state: State, token: Token): string =
  let align = token.tbodyCellVal.align
  if align == "":
    fmt"<td>{state.renderInline(token)}</td>"
  else:
    fmt("<td align=\"{align}\">{state.renderInline(token)}</td>")

proc renderTableRow(state: State, token: Token): string =
  var s = state
  tr(
    "\n",
    token.children.toSeq.map(
      proc(x: Token): string =
        s.renderToken(x)
    ).join("\n"),
    "\n"
  )

proc renderTableHead(state: State, token: Token): string =
  thead(
    "\n",
    state.renderTableRow(token.children.head.value.children.head.value),
    "\n"
  )

proc renderTableBody(state: State, token: Token): string =
  if token.children.head.next == nil:
    return ""
  var s = state
  tbody(
    "\n",
    token.children.tail.value.children.toSeq.map(
      proc(x: Token): string =
        s.renderToken(x)
    ).join("\n"),
  )

proc renderTable(state: State, token: Token): string =
  let thead = state.renderTableHead(token)
  var tbody = state.renderTableBody(token)
  if tbody != "":
    tbody = "\n" & tbody.strip
  table("\n", thead, tbody)

proc renderFencedCode(state: State, token: Token): string =
  var codeHTML = token.doc.escapeCode.escapeQuote
  if codeHTML != "" and not codeHTML.endsWith("\n"):
    codeHTML &= "\n"

  if token.fenceCodeVal.info == "":
    pre(code(codeHTML))
  else:
    pre(code(
      class=fmt"language-{token.fenceCodeVal.info.escapeBackslash.escapeHTMLEntity}",
      codeHTML,
      ))

proc renderLink(state: State, token: Token): string =
  if token.linkVal.title == "":
    a(
      href=token.linkVal.url.escapeBackslash.escapeLinkUrl,
      state.renderInline(token)
    )
  else:
    a(
      href=token.linkVal.url.escapeBackslash.escapeLinkUrl,
      title=token.linkVal.title.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote,
      state.renderInline(token)
    )

proc renderImage(state: State, token: Token): string =
  if token.imageVal.title == "":
    img(
      src=token.imageVal.url.escapeBackslash.escapeLinkUrl,
      alt=state.renderImageAlt(token)
    )
  else:
    img(
      src=token.imageVal.url.escapeBackslash.escapeLinkUrl,
      alt=state.renderImageAlt(token),
      title=token.imageVal.title.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote,
    )

proc renderAutoLink(state: State, token: Token): string =
  a(
    href=token.autoLinkVal.url.escapeLinkUrl.escapeAmpersandSeq,
    token.autoLinkVal.text.escapeAmpersandSeq
  )

proc renderToken(state: State, token: Token): string =
  case token.type
  of ReferenceToken: ""
  of ThematicBreakToken: "<hr />"
  of ParagraphToken: state.renderParagraph(token)
  of ATXHeadingToken: fmt"<h{token.atxHeadingVal.level}>{state.renderInline(token)}</h{token.atxHeadingVal.level}>"
  of SetextHeadingToken: fmt"<h{token.setextHeadingVal.level}>{state.renderInline(token)}</h{token.setextHeadingVal.level}>"
  of IndentedCodeToken: pre(code(token.doc.removeBlankLines.escapeCode.escapeQuote, "\n"))
  of TableToken: state.renderTable(token)
  of THeadToken: state.renderTableHead(token)
  of TBodyToken: state.renderTableBody(token)
  of TableRowToken: state.renderTableRow(token)
  of THeadCellToken: state.renderTableHeadCell(token)
  of TBodyCellToken: state.renderTableBodyCell(token)
  of FencedCodeToken: state.renderFencedCode(token)
  of LinkToken: state.renderLink(token)
  of ImageToken: state.renderImage(token)
  of AutoLinkToken: state.renderAutoLink(token)
  of HTMLBlockToken: token.doc.strip(chars={'\n'})
  of ListItemToken: state.renderListItem(token)
  of UnorderedListToken: state.renderUnorderedList(token)
  of OrderedListToken: state.renderOrderedList(token)
  of BlankLineToken: ""
  of BlockquoteToken: blockquote("\n", state.render(token))
  of TextToken: token.textVal.escapeAmpersandSeq.escapeTag.escapeQuote
  of HTMLEntityToken: token.htmlEntityVal.escapeHTMLEntity.escapeQuote
  of InlineHTMLToken: token.inlineHTMLVal.escapeInvalidHTMLTag
  of EscapeToken: token.escapeVal.escapeAmpersandSeq.escapeTag.escapeQuote
  of EmphasisToken: em(state.renderInline(token))
  of StrongToken: strong(state.renderInline(token))
  of StrikethroughToken: del(token.strikethroughVal)
  of HardLineBreakToken: br() & "\n"
  of CodeSpanToken: code(token.codeSpanVal.escapeAmpersandChar.escapeTag.escapeQuote)
  of SoftLineBreakToken: token.softLineBreakVal
  of DocumentToken: ""

proc render(state: State, token: Token): string =
  var html: string
  for token in token.children.items:
    html = state.renderToken(token)
    if html != "":
      result &= html
      result &= "\n"


proc initMarkdownConfig*(
  escape = true,
  keepHtml = true
): MarkdownConfig =
  MarkdownConfig(
    escape: escape,
    keepHtml: keepHtml
  )

proc markdown*(doc: string, config: MarkdownConfig = initMarkdownConfig()): string =
  var tokens: DoublyLinkedList[Token]
  var state = State(
    doc: doc.strip(chars={'\n'}),
    tokens: tokens,
    ruleSet: gfmRuleSet,
    references: initTable[string, Reference](),
    loose: true
  )
  var document = Token(
    type: DocumentToken,
    doc: doc.strip(chars={'\n'}),
    documentVal: ""
  )
  parse(state, document)
  render(state, document)

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
  stdout.write(
    markdown(
      stdin.readAll,
      config=readCLIOptions()
    )
  )

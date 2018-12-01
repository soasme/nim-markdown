import re, strutils, strformat, tables, sequtils, math, uri, htmlparser, lists, unicode
from sequtils import map
from lists import DoublyLinkedList, prepend, append
from htmlgen import nil, p, br, em, strong, a, img, code, del, blockquote

type
  MarkdownError* = object of Exception ## The error object for markdown parsing and rendering.

  RuleSet = object
    preProcessingRules: seq[TokenType]
    blockRules: seq[TokenType]
    inlineRules: seq[TokenType]
    postProcessingRules: seq[TokenType]

  Delimeter* = object
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

  ReferenceLink = object
    id: string
    text: string

  Image = object
    url: string
    alt: string
    title: string

  AutoLink = object
    text: string
    url: string

  Blockquote = object
    doc: string

  TokenType* {.pure.} = enum
    ParagraphToken,
    BlockquoteToken,
    BlankLineToken,
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
    slice: Slice[int]
    doc: string
    children: DoublyLinkedList[Token]
    case type*: TokenType
    of ParagraphToken: paragraphVal*: Paragraph
    of BlankLineToken: blankLineVal*: string
    of BlockquoteToken: blockquoteVal*: Blockquote
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

  State* = ref object
    doc: string
    ruleSet: RuleSet
    references: Table[string, Reference]
    tokens: DoublyLinkedList[Token]

var simpleRuleSet = RuleSet(
  preProcessingRules: @[],
  blockRules: @[
    ReferenceToken,
    BlockquoteToken,
    BlankLineToken,
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

proc parse(state: var State, token: var Token);
proc parseBlock(state: var State, token: var Token);
proc parseLeafBlockInlines(state: var State, token: var Token);
proc parseLinkInlines*(state: var State, token: var Token, allowNested: bool = false);
proc getLinkText*(doc: string, start: int, slice: var Slice[int], allowNested: bool = false): int;
proc getLinkLabel*(doc: string, start: int, label: var string): int;
proc getLinkDestination*(doc: string, start: int, slice: var Slice[int]): int;
proc getLinkTitle*(doc: string, start: int, slice: var Slice[int]): int;
proc render(state: State, token: Token): string;

proc preProcessing(state: var State, token: var Token) =
  discard

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

proc getBlockStart(token: Token): int =
  if token.children.tail == nil:
    0
  else:
    token.children.tail.value.slice.b

let LAZINESS_TEXT = r"(?:(?! {0,3}>| {0,3}(?:\*|\+|-)(?: |\n|$)| {0,3}\d+(?:\.|\))(?: |\n|$)| {0,3}#| {0,3}`{3,}| {0,3}\*{3}| {0,3}-{3}| {0,3}_{3})[^\n]+(?:\n|$))+"

proc parseParagraph(state: var State, token: var Token): bool =
  let start = token.getBlockStart
  let size = token.doc[start..<token.doc.len].matchLen(re(r"^((?:[^\n]+\n?)(" & LAZINESS_TEXT & "|\n*))"))

  if size == -1:
    return false

  var paragraph = Token(
    type: ParagraphToken,
    slice: (start .. start+size),
    doc: token.doc[start ..< start+size].replace(re"\n\s*", "\n"),
    paragraphVal: Paragraph(
      doc: token.doc[start ..< start+size].replace(re"\n\s*", "\n")
    )
  )

  token.children.append(paragraph)
  return true

proc parseOrderedListItem(doc: string, start=0, marker: var string, listItemDoc: var string, index: var int = 1): int =
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

proc parseUnorderedListItem(doc: string, start=0, marker: var string, listItemDoc: var string): int =
  let markerRegex = re"^(?P<leading> {0,3})(?P<marker>[*\-+])(?: *$| *\n|(?<indent> +)([^\n]+(?:\n|$)))"
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
  if matches[2].len > 1 and matches[2].len <= 4:
    indent = matches[2].len
  elif matches[2].len > 4: # code block indent is still 1.
    listItemDoc = matches[2][1 ..< matches[2].len] & listItemDoc

  var padding = marker.len + leading.len + indent

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

proc parseBlankLine(state: var State, token: var Token): bool =
  let start = token.getBlockStart
  let size = token.doc[start..<token.doc.len].matchLen(re(r"^((?:\s*\n)+)"))

  if size == -1:
    return false

  var blankLine = Token(
    type: BlankLineToken,
    slice: (start .. start+size),
    doc: token.doc[start ..< start+size],
    blankLineVal: token.doc[start ..< start+size]
  )

  token.children.append(blankLine)
  return true

proc parseBlockquote(state: var State, token: var Token): bool =
  let markerContent = re(r"^(( {0,3}>([^\n]*(?:\n|$)))+)")
  var matches: array[3, string]
  let start = token.getBlockStart
  var pos = start
  var size = -1
  var document = ""
  var found = false
  
  while pos < token.doc.len:
    size = token.doc[pos ..< token.doc.len].matchLen(markerContent, matches=matches)

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
    if token.doc[pos ..< token.doc.len].matchLen(re"^\n|$") > -1:
      break

    # find the laziness text
    size = token.doc[pos ..< token.doc.len].matchLen(re("^(" & LAZINESS_TEXT & ")"), matches=matches)

    # blank line in laziness text always breaks the blockquote
    if size == -1:
      break

    # concat the laziness text
    pos += size
    document &= matches[0]

  if not found:
    return false

  var blockquote = Token(
    type: BlockquoteToken,
    slice: (start .. pos),
    doc: document,
    blockquoteVal: Blockquote(
      doc: document
    )
  )
  if document.strip != "":
    parseBlock(state, blockquote)
  token.children.append(blockquote)
  return true

proc parseReference*(state: var State, token: var Token): bool =
  var pos = token.getBlockStart
  var start = pos
  let lastSlice = token.getBlockStart
  let doc = token.doc[pos ..< token.doc.len]

  var markStart = doc.matchLen(re"^ {0,3}\[")
  if markStart == -1:
    return false

  pos += markStart - 1

  var label: string
  var labelSize = getLinkLabel(token.doc, pos, label)

  # Link should have matching ] for [.
  if labelSize == -1:
    return false

  # A link label must contain at least one non-whitespace character.
  if label.find(re"\S") == -1:
    return false

  # An inline link consists of a link text followed immediately by a left parenthesis (
  pos += labelSize # [link]

  if pos >= token.doc.len or token.doc[pos] != ':':
    return false
  pos += 1

  # parse whitespace
  var whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t]*\n?[ \t]*")
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse destination
  var destinationSlice: Slice[int]
  var destinationLen = getLinkDestination(token.doc, pos, destinationslice)

  if destinationLen <= 0:
    return false

  pos += destinationLen

  # parse whitespace
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t]*\n?[ \t]*")
  if whitespaceLen != -1:
    pos += whitespaceLen

  # parse title (optional)
  var titleSlice: Slice[int]
  var titleLen = 0;
  if pos<token.doc.len and( token.doc[pos] == '(' or token.doc[pos] == '\'' or token.doc[pos] == '"'):
    # TODO: validate at least one whitespace before the optional title.

    titleLen = getLinkTitle(token.doc, pos, titleSlice)
    if titleLen >= 0:
      pos += titleLen
      # link title may not contain a blank line
      if token.doc[titleSlice].match(re"\n{2,}"):
        return false

  # parse whitespace, no more non-whitespace is allowed from now.
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^\s*\n+")
  if whitespaceLen != -1:
    pos += whitespaceLen

  # construct token
  var title = ""
  if titleLen > 0:
    title = token.doc[titleSlice]

  var url = token.doc[destinationSlice]

  var reference = Token(
    type: ReferenceToken,
    slice: (start .. pos),
    doc: token.doc[start ..< pos],
    referenceVal: Reference(
      text: label,
      url: url,
      title: title,
    )
  )

  token.children.append(reference)

  if not state.references.contains(label):
    state.references[label] = reference.referenceVal
  return true

proc parseBlock(state: var State, token: var Token) =
  let doc = token.doc
  var ok: bool
  while token.children.tail == nil or token.getBlockStart < doc.len:
    ok = false
    for rule in state.ruleSet.blockRules:
      case rule
      of ReferenceToken: ok = parseReference(state, token)
      of BlockquoteToken: ok = parseBlockquote(state, token)
      of BlankLineToken: ok = parseBlankLine(state, token)
      of ParagraphToken: ok = parseParagraph(state, token)
      else:
        raise newException(MarkdownError, fmt"unknown rule. {token.children.tail.value.slice.b}")
      if ok:
        break
    if not ok:
      raise newException(MarkdownError, fmt"unknown rule. {token.children.tail.value.slice.b}")

proc parseText(state: var State, token: var Token, start: int): int =
  let slice = token.slice
  var text = Token(
    type: TextToken,
    slice: (start .. start+1),
    textVal: token.doc[start ..< start+1],
  )
  token.children.append(text)
  result = 1 # FIXME: should match aggresively.

proc parseSoftLineBreak(state: var State, token: var Token, start: int): int =
  result = token.doc[start ..< token.doc.len].matchLen(re"^ \n *")
  if result != -1:
    token.children.append(Token(
      type: SoftLineBreakToken,
      slice: (start .. start+result),
      softLineBreakVal: "\n"
    ))

proc parseAutoLink(state: var State, token: var Token, start: int): int =
  let slice = token.slice
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
      slice: (start .. start+result),
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
      slice: (start .. start+result),
      autoLinkVal: AutoLink(
        text: fmt"{schema}:{uri}",
        url: fmt"{schema}:{uri}",
      )
    ))
    return result

proc scanInlineDelimeters*(doc: string, start: int, delimeter: var Delimeter) =
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

proc parseDelimeter(state: var State, token: var Token, start: int, delimeters: var DoublyLinkedList[Delimeter]): int =
  if token.doc[start] != '*' and token.doc[start] != '_':
    return -1

  var delimeter = Delimeter(
    token: nil,
    kind: fmt"{token.doc[start]}",
    num: 0,
    originalNum: 0,
    isActive: true,
    canOpen: false,
    canClose: false,
  )

  scanInlineDelimeters(token.doc, start, delimeter)
  if delimeter.num == 0:
    return -1

  result = delimeter.num

  var textToken = Token(
    type: TextToken,
    slice: (start .. start+result),
    textVal: token.doc[start ..< start+result]
  )
  # echo(fmt"added delimeter {delimeter.kind} x {delimeter.num}")
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
    #echo(doc[start ..< doc.len].matchLen(re"^<([^\n<>]*)>"))
    result = doc[start ..< doc.len].matchLen(re"^<([^\n<>]*)>")
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


proc parseInlineLink(state: var State, token: var Token, start: int, labelSlice: Slice[int]): int =
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
  whitespaceLen = token.doc[pos ..< token.doc.len].matchLen(re"^[ \t\n]*")
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
  #echo(destinationLen, destinationSlice)
  var url = token.doc[destinationSlice]
  var text = token.doc[labelSlice.a+1 ..< labelSlice.b]
  #echo((start .. pos + 1))
  var link = Token(
    type: LinkToken,
    slice: (start .. pos + 1),
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

proc parseFullReferenceLink(state: var State, token: var Token, start: int, textSlice: Slice[int]): int =
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
    slice: (start ..< pos),
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

proc parseCollapsedReferenceLink(state: var State, token: var Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var text = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var link = Token(
    type: LinkToken,
    slice: (start ..< label.b + 1),
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

proc parseShortcutReferenceLink(state: var State, token: var Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var text = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var link = Token(
    type: LinkToken,
    slice: (start ..< label.b + 1),
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


proc parseLink*(state: var State, token: var Token, start: int): int =
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

proc parseInlineImage(state: var State, token: var Token, start: int, labelSlice: Slice[int]): int =
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
  #echo(destinationLen, destinationSlice)
  var url = token.doc[destinationSlice]
  var text = token.doc[labelSlice.a+1 ..< labelSlice.b]

  #echo((start .. pos + 1))
  var image = Token(
    type: ImageToken,
    slice: (start-1 .. pos+1),
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

proc parseFullReferenceImage(state: var State, token: var Token, start: int, altSlice: Slice[int]): int =
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
    slice: (start ..< pos),
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

proc parseCollapsedReferenceImage(state: var State, token: var Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var alt = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var image = Token(
    type: ImageToken,
    slice: (start ..< label.b + 3),
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

proc parseShortcutReferenceImage(state: var State, token: var Token, start: int, label: Slice[int]): int =
  var id = token.doc[label.a+1 ..< label.b].toLower.replace(re"\s+", " ")
  var alt = token.doc[label.a+1 ..< label.b]
  if not state.references.contains(id):
    return -1

  var reference = state.references[id]
  var image = Token(
    type: ImageToken,
    slice: (start ..< label.b + 1),
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


proc parseImage*(state: var State, token: var Token, start: int): int =
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
proc parseHTMLEntity*(state: var State, token: var Token, start: int): int =
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
    slice: (start ..< start+size),
    htmlEntityVal: entity
  ))
  return size

proc parseEscape*(state: var State, token: var Token, start: int): int =
  if token.doc[start] != '\\':
    return -1

  let regex = re"^\\([\\`*{}\[\]()#+\-.!_<>~|""$%&',/:;=?@^])"
  let size = token.doc[start ..< token.doc.len].matchLen(regex)
  if size == -1:
    return -1

  token.children.append(Token(
    type: EscapeToken,
    slice: (start ..< start + 2),
    escapeVal: fmt"{token.doc[start+1]}"
  ))
  return 2

proc parseInlineHTML*(state: var State, token: var Token, start: int): int =
  if token.doc[start] != '<':
    return -1
  let regex = re("^(" & HTML_TAG & ")", {RegexFlag.reIgnoreCase})
  var matches: array[5, string]
  var size = token.doc[start ..< token.doc.len].matchLen(regex, matches=matches)

  if size == -1:
    return -1

  token.children.append(Token(
    type: InlineHTMLToken,
    slice: (start ..< start+size),
    inlineHTMLVal: matches[0]
  ))
  return size

proc parseHardLineBreak*(state: var State, token: var Token, start: int): int =
  if token.doc[start] != ' ' and token.doc[start] != '\\':
    return -1

  let size = token.doc[start ..< token.doc.len].matchLen(re"^((?: {2,}\n|\\\n)\s*)")

  if size == -1:
    return -1

  token.children.append(Token(
    type: HardLineBreakToken,
    slice: (start ..< start+size),
    hardLineBreakVal: ""
  ))
  return size

proc parseCodeSpan*(state: var State, token: var Token, start: int): int =
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
      slice: (start ..< start+size),
      textVal: token.doc[start ..< start+size]
    ))
    return size


  token.children.append(Token(
    type: CodeSpanToken,
    slice: (start ..< start+size),
    codeSpanVal: matches[2].strip.replace(re"[ \n]+", " ")
  ))
  return size

proc parseStrikethrough*(state: var State, token: var Token, start: int): int =
  if token.doc[start] != '~':
    return -1

  var matches: array[5, string]
  var size = token.doc[start ..< token.doc.len].matchLen(re"^(~~(?=\S)([\s\S]*?\S)~~)", matches=matches)

  if size == -1:
    return -1

  token.children.append(Token(
    type: StrikethroughToken,
    slice: (start ..< start+size),
    strikethroughVal: matches[1]
  ))
  return size

proc findInlineToken(state: var State, token: var Token, rule: TokenType, start: int, delimeters: var DoublyLinkedList[Delimeter]): int =
  case rule
  of EmphasisToken: result = parseDelimeter(state, token, start, delimeters)
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


proc removeDelimeter*(delimeter: var DoublyLinkedNode[Delimeter]) =
  if delimeter.prev != nil:
    delimeter.prev.next = delimeter.next
  if delimeter.next != nil:
    delimeter.next.prev = delimeter.prev
  delimeter = delimeter.next

proc processEmphasis*(state: var State, token: var Token, delimeterStack: var DoublyLinkedList[Delimeter]) =
  var opener: DoublyLinkedNode[Delimeter] = nil
  var closer: DoublyLinkedNode[Delimeter] = nil
  var oldCloser: DoublyLinkedNode[Delimeter] = nil
  var openerFound = false
  var oddMatch = false
  var useDelims = 0
  var underscoreOpenerBottom: DoublyLinkedNode[Delimeter] = nil
  var asteriskOpenerBottom: DoublyLinkedNode[Delimeter] = nil

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
            removeDelimeter(opener)
        if closer != nil and childNode.value == closer.value.token:
          # remove closer if no text left
          if closer.value.num == 0:
            var tmp = closer.next
            removeDelimeter(closer)
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
        removeDelimeter(oldCloser)

  # after done, remove all delimiters
  while delimeterStack.head != nil:
    removeDelimeter(delimeterStack.head)

proc parseLinkInlines*(state: var State, token: var Token, allowNested: bool = false) =
  var delimeters: DoublyLinkedList[Delimeter]
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
    var ok = false
    var size = -1
    for rule in state.ruleSet.inlineRules:
      if not allowNested and rule == LinkToken:
        continue
      size = findInlineToken(state, token, rule, pos, delimeters)
      if size != -1:
        pos += size
        break
    if size == -1:
      token.children.append(Token(type: TextToken, slice: (index .. index+1), textVal: fmt"{ch}"))
      pos += 1

  processEmphasis(state, token, delimeters)

proc parseLeafBlockInlines(state: var State, token: var Token) =
  var pos = 0
  var delimeters: DoublyLinkedList[Delimeter]

  for index, ch in token.doc[0 ..< token.doc.len].strip:
    if index < pos:
      continue
    var ok = false
    var size = -1
    for rule in state.ruleSet.inlineRules:
      if token.type == rule:
        continue
      size = findInlineToken(state, token, rule, pos, delimeters)
      if size != -1:
        pos += size
        break
    if size == -1:
      token.children.append(Token(type: TextToken, slice: (index .. index+1), textVal: fmt"{ch}"))
      pos += 1

  processEmphasis(state, token, delimeters)

proc isContainerToken(token: Token): bool =
  # TODO: return true for list, list item, blockquote, and task list items
  case token.type
  of BlockquoteToken: true
  else: false

proc parseContainerInlines(state: var State, token: var Token) =
  # TODO: recursively iterate list, list item, bloclquote and task list items
  case token.type
  of BlockquoteToken:
    for childToken in token.children.mitems:
      parseContainerInlines(state, childToken)
  else:
    parseLeafBlockInlines(state, token)

proc parseInline(state: var State, token: var Token) =
  for blockToken in token.children.mitems:
    if isContainerToken(blockToken):
      parseContainerInlines(state, blockToken)
    else:
      parseLeafBlockInlines(state, blockToken)

proc postProcessing(state: var State, token: var Token) =
  discard

proc parse(state: var State, token: var Token) =
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
  token.children.toSeq.map(
    proc(x: Token): string =
      result = renderToken(state, x)
  ).join("")

proc renderImageAlt*(state: State, token: Token): string =
  token.children.toSeq.map(
    proc(x: Token): string =
      case x.type
      of LinkToken: x.linkVal.text
      of ImageToken: x.imageVal.alt
      of EmphasisToken: state.renderInline(x)
      of StrongToken: state.renderInline(x)
      else: renderToken(state, x)
  ).join("")

proc renderToken(state: State, token: Token): string =
  case token.type
  of ReferenceToken: ""
  of ParagraphToken: p(state.renderInline(token))
  of LinkToken:
    if token.linkVal.title == "": a(
      href=token.linkVal.url.escapeBackslash.escapeLinkUrl,
      state.renderInline(token)
    )
    else: a(
      href=token.linkVal.url.escapeBackslash.escapeLinkUrl,
      title=token.linkVal.title.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote,
      state.renderInline(token)
    )
  of ImageToken:
    if token.imageVal.title == "": img(
      src=token.imageVal.url.escapeBackslash.escapeLinkUrl,
      alt=state.renderImageAlt(token)
    )
    else: img(
      src=token.imageVal.url.escapeBackslash.escapeLinkUrl,
      alt=state.renderImageAlt(token),
      title=token.imageVal.title.escapeBackslash.escapeHTMLEntity.escapeAmpersandSeq.escapeQuote,
    )
  of AutoLinkToken: a(href=token.autoLinkVal.url.escapeLinkUrl.escapeAmpersandSeq, token.autoLinkVal.text.escapeAmpersandSeq)
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
  else: raise newException(MarkdownError, fmt"{token.type} rendering not impleted.")

proc render(state: State, token: Token): string =
  var html: string
  for token in token.children.items:
    html = renderToken(state, token)
    if html != "":
      result &= html
      result &= "\n"

proc markdown*(doc: string): string =
  var tokens: DoublyLinkedList[Token]
  var state = State(doc: doc.strip(chars={'\n'}), tokens: tokens, ruleSet: simpleRuleSet, references: initTable[string, Reference]())
  var document = Token(type: DocumentToken, slice: (0 ..< doc.len), doc: doc.strip(chars={'\n'}), documentVal: "")
  parse(state, document)
  render(state, document)

when isMainModule:
  from unittest import check
  import json

  for gfmCase in parseFile("./tests/gfm-spec.json").getElems:
    var exampleId: int = gfmCase["id"].getInt
    var caseName = fmt"gfm example {exampleId}"
    var md = getStr(gfmCase["md"])
    echo(exampleId)
    check markdown(md) == gfmCase["html"].getStr
  check markdown("*a* **b** ***c***") == "<p><em>a</em> <strong>b</strong> <em><strong>c</strong></em></p>\n"

  var slice: Slice[int]
  check getLinkText("[a]", 0, slice) == 3; check slice == (0 .. 2)
  check getLinkText("[[a]", 0, slice) == -1;
  check getLinkText("[[a]", 1, slice) == 3; check slice == (1 .. 3)
  check getLinkText("[[a]]", 0, slice) == 5; check slice == (0 .. 4)
  check getLinkText("[a]]", 0, slice) == 3; check slice == (0 .. 2)
  check getLinkText(r"[a\]]", 0, slice) == 5; check slice == (0 .. 4)
  check getLinkText("[link]", 0, slice) == 6; check slice == (0 .. 5)
  check getLinkText("[link [foo [bar]]]", 0, slice) == 18; check slice == (0 .. 17)
  check getLinkText("[link] bar]", 0, slice) == 6; check slice == (0 .. 5)
  check getLinkText("[link [bar]", 0, slice) == -1;
  check getLinkText(r"[link \[bar]", 0, slice) == 12; check slice == (0 .. 11)
  check getLinkText("[foo [bar](/uri)]", 0, slice) == -1
  check getLinkText("[foo *[bar [baz](/uri)](/uri)*]", 0, slice) == -1
  check getLinkText("![[[foo](uri1)](uri2)]", 1, slice, allowNested=true) == 21; check slice == (1 .. 21)
  check getLinkText("*[foo*]", 1, slice) == 6; check slice == (1 .. 6)
  check getLinkText("[foo`]`", 0, slice) == -1;
  check getLinkText("[foo`]`]", 0, slice) == 8; check slice == (0 .. 7);
  check getLinkText("[foo <a href=]>]", 0, slice) == 16; check slice == (0 .. 15);
  check getLinkText("[[foo](/uri)]", 0, slice) == -1
  check getLinkText("[![foo](/uri)]", 0, slice) == 14; check slice == (0 .. 13)

  
  var doc = ""
  doc = "(<a>)"; check getLinkDestination(doc, 1, slice) == 3; check doc[slice] == "a"
  
  doc = "(/uri)";  echo doc; check getLinkDestination(doc, 1, slice) == 4; check doc[slice] == "/uri"
  doc = "(/uri \"title\")"; echo doc;  check getLinkDestination(doc, 1, slice) == 4; check doc[slice] == "/uri"
  doc = "()";  echo doc; check getLinkDestination(doc, 1, slice) == 0; check doc[slice] == ""
  doc = "(<>)";  echo doc; check getLinkDestination(doc, 1, slice) == 2; check doc[slice] == ""
  doc = "(/my uri)";  echo doc; check getLinkDestination(doc, 1, slice) == 3; check doc[slice] == "/my" # we'll abort at link title step
  doc = "(</my uri>)";  echo doc; check getLinkDestination(doc, 1, slice) == 9; check doc[slice] == "/my uri"
  doc = "(foo\nbar)"; echo doc; check getLinkDestination(doc, 1, slice) == 3; # we'll abort at link title step
  doc = "(<foo\nbar>)"; echo doc; check getLinkDestination(doc, 1, slice) == -1;
  doc = r"(\(foo\))";  echo doc; check getLinkDestination(doc, 1, slice) == 7; check doc[slice] == r"\(foo\)"
  doc = r"(foo(and(bar)))";  echo doc; check getLinkDestination(doc, 1, slice) == 13; check doc[slice] == r"foo(and(bar))"
  doc = r"(foo\(and\(bar\))";  echo doc; check getLinkDestination(doc, 1, slice) == 15; check doc[slice] == r"foo\(and\(bar\)"
  doc = r"(<foo(and(bar)>)";  echo doc; check getLinkDestination(doc, 1, slice) == 14; check doc[slice] == r"foo(and(bar)"
  doc = r"(foo\)\:)";  echo doc; check getLinkDestination(doc, 1, slice) == 7; check doc[slice] == r"foo\)\:"
  doc = r"(#fragment)";  echo doc; check getLinkDestination(doc, 1, slice) == 9; check doc[slice] == r"#fragment"
  doc = "(\"title\")";   echo doc; check getLinkDestination(doc, 1, slice) == 7; check doc[slice] == "\"title\""
  doc = "(   /uri\n  \"title\""; echo doc; check getLinkDestination(doc, 4, slice) == 4; check doc[slice] == "/uri"

  check getLinkTitle("/url \"title\"", 5, slice) == 7; check "/url \"title\""[slice] == "title"
  check getLinkTitle("/url 'title'", 5, slice) == 7; check "/url 'title'"[slice] == "title"
  check getLinkTitle("/url (title)", 5, slice) == 7; check "/url (title)"[slice] == "title"
  check getLinkTitle(""""title \"&quot;"""", 0, slice) == 16; check """"title \"&quot;""""[slice] == "title \"&quot;"

  var label = ""
  check getLinkLabel("[a]", 0, label) == 3; check label == "a"
  check getLinkLabel("[a]]", 0, label) == 3; check label == "a"
  check getLinkLabel("[a[]", 0, label) == -1


  var marker = "*"
  var listItemDoc = ""
  var index = 1

  # 255
  check parseUnorderedListItem("*", 0, marker, listItemDoc) == 1
  check listItemDoc == ""
  check marker == "*"

  check parseUnorderedListItem("*a", 0, marker, listItemDoc) == -1

  check parseUnorderedListItem("* a", 0, marker, listItemDoc) == 3
  check listItemDoc == "a"
  check marker == "*"

  check parseUnorderedListItem("*  a", 0, marker, listItemDoc) == 4
  check listItemDoc == "a"
  check marker == "*"

  check parseUnorderedListItem(" * a", 0, marker, listItemDoc) == 4
  check listItemDoc == "a"
  check marker == "*"

  check parseUnorderedListItem("  * a", 0, marker, listItemDoc) == 5
  check listItemDoc == "a"
  check marker == "*"

  check parseUnorderedListItem("   * a", 0, marker, listItemDoc) == 6
  check listItemDoc == "a"
  check marker == "*"

  check parseUnorderedListItem("    * a", 0, marker, listItemDoc) == -1

  marker = "+"
  check parseUnorderedListItem("+ a", 0, marker, listItemDoc) == 3
  check listItemDoc == "a"
  check marker == "+"

  marker = "-"
  check parseUnorderedListItem("- a", 0, marker, listItemDoc) == 3
  check listItemDoc == "a"
  check marker == "-"

  # 271, A list item can contain a heading
  marker = "-"
  check parseUnorderedListItem("- # Foo\n- Bar\n  ---\n  baz", 0, marker, listItemDoc) == 8
  check listItemDoc == "# Foo\n"
  check marker == "-"
  check parseUnorderedListItem("- # Foo\n- Bar\n  ---\n  baz", 8, marker, listItemDoc) == 17
  check listItemDoc == "Bar\n---\nbaz"
  check marker == "-"

  # 270, A list may be the first block in a list item.
  marker = "."
  check parseOrderedListItem("1. - 2. foo", 0, marker, listItemDoc, index) == 11
  check listItemDoc == "- 2. foo"
  check marker == "."
  check index == 1
  marker = "-"
  check parseUnorderedListItem("1. - 2. foo", 3, marker, listItemDoc) == 8
  check listItemDoc == "2. foo"
  check marker == "-"
  marker = "."
  check parseOrderedListItem("1. - 2. foo", 5, marker, listItemDoc, index) == 6
  check listItemDoc == "foo"
  check marker == "."
  check index == 2

  # 269, A list may be the first block in a list item
  marker = "-"
  check parseUnorderedListItem("- - foo", 0, marker, listItemDoc) == 7
  check listItemDoc == "- foo"
  check marker == "-"
  check parseUnorderedListItem("- - foo", 2, marker, listItemDoc) == 5
  check listItemDoc == "foo"
  check marker == "-"

  # 268, Three is not enough
  marker = ")"
  check parseOrderedListItem("10) foo\n   - bar", 0, marker, listItemDoc, index) == 8
  check listItemDoc == "foo\n"
  check marker == ")"
  check index == 10

  # 267, Here we need four, because the list marker is wider
  marker = ")"
  check parseOrderedListItem("10) foo\n    - bar", 0, marker, listItemDoc, index) == 17
  check listItemDoc == "foo\n- bar"
  check marker == ")"
  check index == 10

  # 266, One is not enough
  marker = "-"
  check parseUnorderedListItem("- foo\n - bar\n  - baz\n   - boo", 0, marker, listItemDoc) == 6
  check listItemDoc == "foo\n"
  check marker == "-"
  check parseUnorderedListItem("- foo\n - bar\n  - baz\n   - boo", 6, marker, listItemDoc) == 7
  check listItemDoc == "bar\n"
  check parseUnorderedListItem("- foo\n - bar\n  - baz\n   - boo", 13, marker, listItemDoc) == 8
  check listItemDoc == "baz\n"
  check parseUnorderedListItem("- foo\n - bar\n  - baz\n   - boo", 21, marker, listItemDoc) == 8
  check listItemDoc == "boo"

  # 265, in this case we need two spaces indent
  marker = "-"
  check parseUnorderedListItem("- foo\n  - bar\n    - baz\n      - boo", 0, marker, listItemDoc) == 35
  check listItemDoc == "foo\n- bar\n  - baz\n    - boo"
  check parseUnorderedListItem("foo\n- bar\n  - baz\n    - boo", 4, marker, listItemDoc) == 23
  check listItemDoc == "bar\n- baz\n  - boo"
  check parseUnorderedListItem("bar\n- baz\n  - boo", 4, marker, listItemDoc) == 13
  check listItemDoc == "baz\n- boo"
  check parseUnorderedListItem("baz\n- boo", 4, marker, listItemDoc) == 5
  check listItemDoc == "boo"

  # 263, Laziness.
  marker = ""
  check parseOrderedListItem("1. > Blockquote\ncontinued here.", 0, marker, listItemDoc, index) == 31
  check listItemDoc == "> Blockquote\ncontinued here."
  check marker == "."
  check index == 1

  # 262, Indentation can be partially deleted.
  marker = ""
  check parseOrderedListItem("  1. a\n    b.", 0, marker, listItemDoc, index) == 13
  check listItemDoc == "a\n    b."
  check marker == "."

  # 261, lazy continuation lines.
  marker = ""
  check parseOrderedListItem("  1.  a\n2\n\n          code\n\n      > quote.", 0, marker, listItemDoc, index) == 41
  check listItemDoc == "a\n2\n\n    code\n\n> quote."

  # 260, Four spaces indent gives a code block
  marker = ""
  check parseOrderedListItem("    1. a", 0, marker, listItemDoc, index) == -1

  # 258, Indented two spaces
  marker = ""
  check parseOrderedListItem("  1.  A\n      B\n\n          C\n\n      > D", 0, marker, listItemDoc, index) == 39
  check listItemDoc == "A\nB\n\n    C\n\n> D"
  check marker == "."
  check index == 1


  # 257, Indented one space
  marker = ""
  check parseOrderedListItem(" 1.  A\n     B\n\n         C\n\n     > D", 0, marker, listItemDoc, index) == 35
  check listItemDoc == "A\nB\n\n    C\n\n> D"
  check marker == "."
  check index == 1

  # 254, an empty ordered list item
  marker = ""
  check parseOrderedListItem("1. a\n2.\n3. c", 0, marker, listItemDoc, index) == 5
  check listItemDoc == "a\n"
  check parseOrderedListItem("1. a\n2.\n3. c", 5, marker, listItemDoc, index) == 3
  check listItemDoc == ""
  check parseOrderedListItem("1. a\n2.\n3. c", 8, marker, listItemDoc, index) == 4
  check listItemDoc == "c"

  # 253, It does not matter whether there are spaces following the list marker
  check parseOrderedListItem("1. a\n2.   \n3. c", 0, marker, listItemDoc, index) == 5
  check listItemDoc == "a\n"
  check parseOrderedListItem("1. a\n2.   \n3. c", 5, marker, listItemDoc, index) == 6
  check listItemDoc == ""
  check parseOrderedListItem("1. a\n2.   \n3. c", 11, marker, listItemDoc, index) == 4
  check listItemDoc == "c"

  # 252 an empty bullet list item
  marker = ""
  check parseUnorderedListItem("- a\n-\n- c", 0, marker, listItemDoc) == 4
  check listItemDoc == "a\n"
  check parseUnorderedListItem("- a\n-\n- c", 4, marker, listItemDoc) == 2
  check listItemDoc == ""
  check parseUnorderedListItem("- a\n-\n- c", 6, marker, listItemDoc) == 3
  check listItemDoc == "c"

  # 251, A list item can begin with at most one blank line.
  marker= ""
  check parseUnorderedListItem("-\n\n  foo", 0, marker, listItemDoc) == 3
  check listItemDoc == "\n"

  # 250, When the list item starts with a blank line, the number of spaces following the list marker doesn’t change the required indentation
  marker = ""
  check parseUnorderedListItem("-   \n  foo", 0, marker, listItemDoc) == 10
  check listItemDoc == "foo"

  # 249, list items that start with a blank line but are not empty
  marker = ""
  check parseUnorderedListItem("-\n  a\n-\n  a\n  b\n  c\n-\n        baz", 0, marker, listItemDoc) == 6
  check listItemDoc == "a\n"
  check parseUnorderedListItem("-\n  a\n-\n  a\n  b\n  c\n-\n        baz", 6, marker, listItemDoc) == 14
  check listItemDoc == "a\nb\nc\n"
  check parseUnorderedListItem("-\n  a\n-\n  a\n  b\n  c\n-\n      baz", 20, marker, listItemDoc) == 11
  check listItemDoc == "    baz"

  # 248 when a block begins with 1-3 spaces indent, the indentation can always be removed without a change
  marker = ""
  check parseUnorderedListItem("-  foo\n\n   bar", 0, marker, listItemDoc) == 14
  check listItemDoc == "foo\n\nbar"

  # 247 the first block begins with a three-space indent, 
  marker = ""
  check parseUnorderedListItem("-    foo\n\n  bar", 0, marker, listItemDoc) == 10
  check listItemDoc == "foo\n\n"

  # 244, the first block begins with code block.
  marker = ""
  check parseUnorderedListItem("-     foo\n\n  p", 0, marker, listItemDoc) == 14
  check listItemDoc == "    foo\n\np"
  marker = ""
  check parseOrderedListItem("1.     foo\n\n   p", 0, marker, listItemDoc, index) == 16
  check listItemDoc == "    foo\n\np"

  # 242, code: it is 11 spaces.
  marker = ""
  check parseUnorderedListItem("  -  a\n\n         code", 0, marker, listItemDoc) == 21
  check listItemDoc == "a\n\n    code"
  marker = ""
  check parseOrderedListItem("  1.  a\n\n          code", 0, marker, listItemDoc, index) == 23
  check listItemDoc == "a\n\n    code"

  # 241, code: second block.
  marker = ""
  check parseUnorderedListItem("- a\n\n      code", 0, marker, listItemDoc) == 15
  check listItemDoc == "a\n\n    code"
  marker = ""
  check parseOrderedListItem("1.  a\n\n        code", 0, marker, listItemDoc, index) == 19
  check listItemDoc == "a\n\n    code"

  # 239, start number may start with 0.
  marker = ""
  check parseOrderedListItem("003. ok", 0, marker, listItemDoc, index) == 7
  check index == 3
  marker = ""
  check parseOrderedListItem("0. ok", 0, marker, listItemDoc, index) == 5
  check index == 0
  check parseOrderedListItem("123456789. ok", 0, marker, listItemDoc, index) == 13
  check index == 123456789
  check parseOrderedListItem("0123456789. ok", 0, marker, listItemDoc, index) == -1

  # 235, preserve empty lines within the code block verbatim
  marker = ""
  check parseUnorderedListItem("- A\n\n      B\n\n      C", 0, marker, listItemDoc) == 21
  check listItemDoc == "A\n\n    B\n\n    C"
  marker = ""
  check parseOrderedListItem("1. A\n\n       B\n\n       C", 0, marker, listItemDoc, index) == 24
  check listItemDoc == "A\n\n    B\n\n    C"

  # 274, Changing the bullet or ordered list delimiter starts a new list.
  marker = ""
  check parseUnorderedListItem("- a\n- b\n+ c", 0, marker, listItemDoc) == 4
  check parseUnorderedListItem("- a\n- b\n+ c", 4, marker, listItemDoc) == 4
  check parseUnorderedListItem("- a\n- b\n+ c", 8, marker, listItemDoc) == -1
  marker = ""
  check parseUnorderedListItem("- a\n- b\n+ c", 8, marker, listItemDoc) == 3

  # 275,
  marker = ""
  check parseOrderedListItem("1. a\n2. b\n3) c", 0, marker, listItemDoc, index) == 5
  check parseOrderedListItem("1. a\n2. b\n3) c", 5, marker, listItemDoc, index) == 5
  check parseOrderedListItem("1. a\n2. b\n3) c", 10, marker, listItemDoc, index) == -1

  # 279 any number of blank lines between items
  marker = ""
  check parseUnorderedListItem("- a\n\n- b\n\n\n- c", 0, marker, listItemDoc) == 5
  check parseUnorderedListItem("- a\n\n- b\n\n\n- c", 5, marker, listItemDoc) == 6
  check parseUnorderedListItem("- a\n\n- b\n\n\n- c", 11, marker, listItemDoc) == 3

  # 280
  marker = ""
  check parseUnorderedListItem("- a\n  - aa\n    - aaa\n\n\n      aab", 0, marker, listItemDoc) == 32
  check listItemDoc == "a\n- aa\n  - aaa\n\n    aab"

  # 281, separate items
  marker = ""
  check parseUnorderedListItem("- a\n- b\n\n<!-- -->", 0, marker, listItemDoc) == 4
  check parseUnorderedListItem("- a\n- b\n\n<!-- -->", 4, marker, listItemDoc) == 5

  # 282, separate items
  marker = ""
  check parseUnorderedListItem("-   a\n\n    a\n\n-   b\n\n<!-- -->", 0, marker, listItemDoc) == 14
  check parseUnorderedListItem("-   a\n\n    a\n\n-   b\n\n<!-- -->", 14, marker, listItemDoc) == 7

  # 283, List items need not be indented to the same level
  marker = ""
  check parseUnorderedListItem("- a\n - b\n  - c\n", 0, marker, listItemDoc) == 4
  check parseUnorderedListItem("- a\n - b\n  - c\n", 4, marker, listItemDoc) == 5
  check parseUnorderedListItem("- a\n - b\n  - c\n", 9, marker, listItemDoc) == 6
  marker = ""
  check parseOrderedListItem("1. a\n 2. b\n  3. c", 0, marker, listItemDoc, index) == 5
  check parseOrderedListItem("1. a\n 2. b\n  3. c", 5, marker, listItemDoc, index) == 6
  check parseOrderedListItem("1. a\n 2. b\n  3. c", 11, marker, listItemDoc, index) == 6

  # 285, list items may not be indented more than three spaces.
  marker = ""
  check parseUnorderedListItem("- a\n    - e", 0, marker, listItemDoc) == 11
  check listItemDoc == "a\n  - e"

  # 286, indented four spaces and preceded by a blank line.
  marker = ""
  check parseOrderedListItem("  1. a\n\n    2. b", 0, marker, listItemDoc, index) == 8
  check parseOrderedListItem("  1. a\n\n    2. b", 8, marker, listItemDoc, index) == -1

  # 287, loose list
  marker = ""
  check parseUnorderedListItem("- a\n- b\n\n- c", 0, marker, listItemDoc) == 4
  check listItemDoc == "a\n"
  check parseUnorderedListItem("- a\n- b\n\n- c", 4, marker, listItemDoc) == 5
  check listItemDoc == "b\n\n"
  check parseUnorderedListItem("- a\n- b\n\n- c", 9, marker, listItemDoc) == 3
  check listItemDoc == "c"

  # 288,  empty second item
  marker = ""
  check parseUnorderedListItem("* a\n*\n\n* c", 0, marker, listItemDoc) == 4
  check listItemDoc == "a\n"
  check parseUnorderedListItem("* a\n*\n\n* c", 4, marker, listItemDoc) == 3
  check listItemDoc == "\n"
  check parseUnorderedListItem("* a\n*\n\n* c", 7, marker, listItemDoc) == 3
  check listItemDoc == "c"

  # 289, 
  marker = ""
  check parseUnorderedListItem("- a\n- b\n\n  c\n- d", 0, marker, listItemDoc) == 4
  check listItemDoc == "a\n"
  check parseUnorderedListItem("- a\n- b\n\n  c\n- d", 4, marker, listItemDoc) == 9
  check listItemDoc == "b\n\nc\n"
  check parseUnorderedListItem("- a\n- b\n\n  c\n- d", 13, marker, listItemDoc) == 3
  check listItemDoc == "d"

  # 291
  marker = ""
  check parseUnorderedListItem("- a\n- ```\n  b\n\n  ```\n- c", 0, marker, listItemDoc) == 4
  check listItemDoc == "a\n"
  check parseUnorderedListItem("- a\n- ```\n  b\n\n  ```\n- c", 4, marker, listItemDoc) == 17
  check listItemDoc == "```\nb\n\n```\n"
  check parseUnorderedListItem("- a\n- ```\n  b\n\n  ```\n- c", 21, marker, listItemDoc) == 3
  check listItemDoc == "c"

  # 292
  marker = ""
  check parseUnorderedListItem("- a\n  - b\n  - c\n- d", 0, marker, listItemDoc) == 16
  check listItemDoc == "a\n- b\n- c\n"
  check parseUnorderedListItem("- a\n  - b\n  - c\n- d", 16, marker, listItemDoc) == 3

  # 298
  marker = ""
  check parseUnorderedListItem("* a\n  * b\n\n  c", 0, marker, listItemDoc) == 14
  check listItemDoc == "a\n* b\n\nc"

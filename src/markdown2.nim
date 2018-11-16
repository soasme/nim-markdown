import re, strutils, strformat, tables, sequtils, math, uri, htmlparser, lists, unicode
from sequtils import map
from lists import DoublyLinkedList, prepend, append
from htmlgen import nil, p, br, em, strong, a, img

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

  TokenType* {.pure.} = enum
    ParagraphToken,
    TextToken,
    AutoLinkToken,
    LinkToken,
    ImageToken,
    EmphasisToken,
    StrongToken,
    SoftLineBreakToken,
    DummyToken

  Token* = ref object
    slice: Slice[int]
    children: DoublyLinkedList[Token]
    case type*: TokenType
    of ParagraphToken: paragraphVal*: Paragraph
    of TextToken: textVal*: string
    of EmphasisToken: emphasisVal*: string
    of AutoLinkToken: autoLinkVal*: AutoLink
    of LinkToken: linkVal*: Link
    of ImageToken: imageVal*: Image
    of StrongToken: strongVal*: string
    of SoftLineBreakToken: softLineBreakVal*: string
    of DummyToken: dummyVal*: string

  State* = ref object
    doc: string
    ruleSet: RuleSet
    tokens: DoublyLinkedList[Token]

var simpleRuleSet = RuleSet(
  preProcessingRules: @[],
  blockRules: @[ParagraphToken],
  inlineRules: @[
    EmphasisToken, # including strong.
    ImageToken,
    AutoLinkToken,
    LinkToken,
    SoftLineBreakToken,
    TextToken,
  ],
  postProcessingRules: @[],
)

proc parse(state: var State);
proc parseLeafBlockInlines(state: var State, token: var Token);
proc parseLinkInlines*(state: var State, token: var Token, allowNested: bool = false);

proc preProcessing(state: var State) =
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

proc parseParagraph(state: var State): bool =
  let slice = state.tokens.tail.value.slice
  let size = state.doc[slice.b..<state.doc.len].matchLen(re(r"([^\n]+\n?)+\n*"))

  if size == -1:
    return false

  var token = Token(
    type: ParagraphToken,
    slice: (slice.b .. slice.b+size),
    paragraphVal: Paragraph(
      doc: state.doc[slice.b ..< slice.b+size],
    )
  )

  state.tokens.append(token)
  return true

proc parseBlock(state: var State) =
  var ok: bool
  while state.tokens.tail.value.slice.b < state.doc.len:
    ok = false
    for rule in state.ruleSet.blockRules:
      case rule
      of ParagraphToken: ok = parseParagraph(state)
      else:
        raise newException(MarkdownError, fmt"unknown rule. {state.tokens.tail.value.slice.b}")
      if ok:
        break
    if not ok:
      raise newException(MarkdownError, fmt"unknown rule. {state.tokens.tail.value.slice.b}")

proc parseText(state: var State, token: var Token, start: int): int =
  let slice = token.slice
  #echo(fmt"text: {start} {state.doc}")
  var text = Token(
    type: TextToken,
    slice: (start .. start+1),
    textVal: state.doc[start..start],
  )
  token.children.append(text)
  result = 1 # FIXME: should match aggresively.

proc parseSoftLineBreak(state: var State, token: var Token, start: int): int =
  result = state.doc[start ..< state.doc.len].matchLen(re"^ \n *")
  if result != -1:
    token.children.append(Token(
      type: SoftLineBreakToken,
      slice: (start .. start+result),
      softLineBreakVal: "\n"
    ))

proc parseAutoLink(state: var State, token: var Token, start: int): int =
  let slice = token.slice
  if state.doc[start] != '<':
    return -1

  let EMAIL_RE = r"^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>"
  var emailMatches: array[1, string]
  result = state.doc[start ..< state.doc.len].matchLen(re(EMAIL_RE, {RegexFlag.reIgnoreCase}), matches=emailMatches)

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
  result = state.doc[start ..< state.doc.len].matchLen(re(LINK_RE, {RegexFlag.reIgnoreCase}), matches=linkMatches)

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
  if state.doc[start] != '*' and state.doc[start] != '_':
    return -1

  var delimeter = Delimeter(
    token: nil,
    kind: fmt"{state.doc[start]}",
    num: 0,
    originalNum: 0,
    isActive: true,
    canOpen: false,
    canClose: false,
  )

  scanInlineDelimeters(state.doc, start, delimeter)
  if delimeter.num == 0:
    return -1

  result = delimeter.num

  var textToken = Token(
    type: TextToken,
    slice: (start .. start+result),
    textVal: state.doc[start ..< start+result]
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
    urlLen = i
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true
      continue
    elif ch.int < 0x20 or ch.int == 0x7f or ch == ' ':
      break
    elif ch == '(':
      level += 1
    elif ch == ')':
      level -= 1
      if level == 0:
        break
  #echo(fmt"{level} {urlLen}")
  if level > 1:
    return -1
  if urlLen == -1:
     return -1
  slice = (start .. start+urlLen-1)
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

proc getLinkLabelSlice*(doc: string, start: int, slice: var Slice[int], allowNested: bool = false): int =
  # based on assumption: state.doc[start] = '['
  if doc[start] != '[':
    raise newException(MarkdownError, fmt"{start} is not [.")
  var level = 0
  var isEscaping = false
  for i, ch in doc[start ..< doc.len]:
    if isEscaping:
      isEscaping = false
      continue
    elif ch == '\\':
      isEscaping = true
    elif ch == '[':
      level += 1
    elif ch == ']':
      level -= 1
    elif ch == '<':
      # abort if it's an HTML tag or autolink.
      if doc[start+i ..< doc.len].matchLen(re"^<\w+[^>]*>") != -1:
        return -1
    elif ch == '`':
      if doc[start+i ..< doc.len].matchLen(re"^`[^`]+`") != -1:
        return -1
    if level == 0:
      # if not allow but detect nested, abort.
      if not allowNested and doc[start .. start+i].find(re"[^!]\[[^\]]+\]\(.*\)") != -1:
        return -1
      slice = (start .. start+i)
      return i+1
  return -1


proc parseInlineLink(state: var State, token: var Token, start: int, labelSlice: Slice[int]): int =
  if state.doc[start] != '[':
    return -1

  var pos = labelSlice.b + 2 # [link](

  # parse whitespace
  var whitespaceLen = state.doc[pos ..< state.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # parse destination
  var destinationSlice: Slice[int]
  var destinationLen = getLinkDestination(state.doc, pos, destinationslice)
  if destinationLen == -1:
    return -1

  pos += destinationLen

  # parse whitespace
  whitespaceLen = state.doc[pos ..< state.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # parse title (optional)
  if state.doc[pos] != '(' and state.doc[pos] != '\'' and state.doc[pos] != '"' and state.doc[pos] != ')':
    return -1
  var titleSlice: Slice[int]
  var titleLen = getLinkTitle(state.doc, pos, titleSlice)

  if titleLen >= 0:
    pos += titleLen

  # parse whitespace
  whitespaceLen = state.doc[pos ..< state.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # require )
  if pos >= state.doc.len:
    return -1
  if state.doc[pos] != ')':
    return -1

  # construct token
  var title = ""
  if titleLen >= 0:
    title = state.doc[titleSlice]
  #echo(destinationLen, destinationSlice)
  var url = state.doc[destinationSlice]
  var text = state.doc[labelSlice.a+1 ..< labelSlice.b]
  #echo((start .. pos + 1))
  var link = Token(
    type: LinkToken,
    slice: (start .. pos + 1),
    linkVal: Link(
      text: text,
      url: url,
      title: title,
    )
  )
  parseLinkInlines(state, link)
  token.children.append(link)
  result = pos - start + 1

proc parseFullReferenceLink(state: var State, token: var Token, start: int, label: Slice[int]): int =
  -1

proc parseCollapsedReferenceLink(state: var State, token: var Token, start: int, label: Slice[int]): int =
  -1

proc parseShortcutReferenceLink(state: var State, token: var Token, start: int, label: Slice[int]): int =
  -1

proc parseLink*(state: var State, token: var Token, start: int): int =
  # Link should start with [
  if state.doc[start] != '[':
    return -1

  var labelSlice: Slice[int]
  result = getLinkLabelSlice(state.doc, start, labelSlice)

  # Link should have matching ] for [.
  if result == -1:
    return -1

  # An inline link consists of a link text followed immediately by a left parenthesis (
  if labelSlice.b + 1 < state.doc.len and state.doc[labelSlice.b + 1] == '(':
    return parseInlineLink(state, token, start, labelSlice)

  # A collapsed reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document, followed by the string []. 
  elif labelSlice.b + 2 < state.doc.len and state.doc[labelSlice.b .. labelSlice.b+2] == "[]":
    return parseCollapsedReferenceLink(state, token, start, labelSlice)

  # A full reference link consists of a link text immediately followed by a link label 
  # that matches a link reference definition elsewhere in the document.
  if labelSlice.b + 1 < state.doc.len and state.doc[labelSlice.b + 1] == '[':
    return parseFullReferenceLink(state, token, start, labelSlice)

  # A shortcut reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document and is not followed by [] or a link label.
  else:
    return parseShortcutReferenceLink(state, token, start, labelSlice)

proc parseInlineImage(state: var State, token: var Token, start: int, labelSlice: Slice[int]): int =
  var pos = labelSlice.b + 2 # ![link](

  # parse whitespace
  var whitespaceLen = state.doc[pos ..< state.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # parse destination
  var destinationSlice: Slice[int]
  var destinationLen = getLinkDestination(state.doc, pos, destinationslice)
  if destinationLen == -1:
    return -1

  pos += destinationLen

  # parse whitespace
  whitespaceLen = state.doc[pos ..< state.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # parse title (optional)
  if state.doc[pos] != '(' and state.doc[pos] != '\'' and state.doc[pos] != '"' and state.doc[pos] != ')':
    return -1
  var titleSlice: Slice[int]
  var titleLen = getLinkTitle(state.doc, pos, titleSlice)

  if titleLen >= 0:
    pos += titleLen

  # parse whitespace
  whitespaceLen = state.doc[pos ..< state.doc.len].matchLen(re"^[ \t\n]*")
  pos += whitespaceLen

  # require )
  if pos >= state.doc.len:
    return -1
  if state.doc[pos] != ')':
    return -1

  # construct token
  var title = ""
  if titleLen >= 0:
    title = state.doc[titleSlice]
  #echo(destinationLen, destinationSlice)
  var url = state.doc[destinationSlice]
  var text = state.doc[labelSlice.a+1 ..< labelSlice.b]
  #echo((start .. pos + 1))
  var image = Token(
    type: ImageToken,
    slice: (start-1 .. pos+1),
    imageVal: Image(
      alt: text,
      url: url,
      title: title,
    )
  )
  parseLinkInlines(state, image, allowNested=true)
  token.children.append(image)
  result = pos - start + 2

proc parseImage*(state: var State, token: var Token, start: int): int =
  # Image should start with ![
  #echo(state.doc[start ..< state.doc.len])
  if not state.doc[start ..< state.doc.len].match(re"^!\["):
    return -1

  var labelSlice: Slice[int]
  var labelSize = getLinkLabelSlice(state.doc, start+1, labelSlice, allowNested=true)

  # Image should have matching ] for [.
  if labelSize == -1:
    return -1

  # An inline image consists of a link text followed immediately by a left parenthesis (
  if labelSlice.b + 1 < state.doc.len and state.doc[labelSlice.b + 1] == '(':
    return parseInlineImage(state, token, start+1, labelSlice)

  # A collapsed reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document, followed by the string []. 
  elif labelSlice.b + 2 < state.doc.len and state.doc[labelSlice.b .. labelSlice.b+2] == "[]":
    return parseCollapsedReferenceLink(state, token, start, labelSlice)

  # A full reference link consists of a link text immediately followed by a link label 
  # that matches a link reference definition elsewhere in the document.
  if labelSlice.b + 1 < state.doc.len and state.doc[labelSlice.b + 1] == '[':
    return parseFullReferenceLink(state, token, start, labelSlice)

  # A shortcut reference link consists of a link label that matches a link reference 
  # definition elsewhere in the document and is not followed by [] or a link label.
  else:
    return parseShortcutReferenceLink(state, token, start, labelSlice)

proc findInlineToken(state: var State, token: var Token, rule: TokenType, start: int, delimeters: var DoublyLinkedList[Delimeter]): int =
  case rule
  of EmphasisToken: result = parseDelimeter(state, token, start, delimeters)
  of AutoLinkToken: result = parseAutoLink(state, token, start)
  of LinkToken: result = parseLink(state, token, start)
  of ImageToken: result = parseImage(state, token, start)
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
    pos = token.slice.a + 1
    size = token.linkVal.text.len - 1
  elif token.type == ImageToken:
    pos = token.slice.a + 2
    size = token.imageVal.alt.len
  else:
    raise newException(MarkdownError, fmt"{token.type} has no link inlines.")
  for index, ch in state.doc[pos .. pos+size]:
    if token.slice.a+1+index < pos:
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
  var pos = token.slice.a
  var delimeters: DoublyLinkedList[Delimeter]
  
  for index, ch in state.doc[token.slice.a ..< token.slice.b].strip:
    #echo(token.slice, index, " ", pos)
    if token.slice.a + index < pos:
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
  of ParagraphToken: false
  else: false

proc parseContainerInlines(state: var State, token: var Token): untyped =
  # TODO: recursively iterate list, list item, bloclquote and task list items
  case token.type
  of ParagraphToken: parseLeafBlockInlines(state, token)
  else:
    raise newException(MarkdownError, fmt"{token.type} walking inlines unsupported.")

proc parseInline(state: var State) =
  for blockToken in state.tokens.mitems:
    if isContainerToken(blockToken):
      parseContainerInlines(state, blockToken)
    else:
      parseLeafBlockInlines(state, blockToken)

proc postProcessing(state: var State) =
  discard

proc parse(state: var State) =
  preProcessing(state)
  parseBlock(state)
  parseInline(state)
  postProcessing(state)

proc toSeq(tokens: DoublyLinkedList[Token]): seq[Token] =
  result = newSeq[Token]()
  for token in tokens.items:
    result.add(token)

proc renderToken(token: Token): string;
proc renderInline(token: Token): string =
  token.children.toSeq.map(
    proc(x: Token): string =
      result = renderToken(x)
  ).join("")

proc renderImageAlt*(token: Token): string =
  token.children.toSeq.map(
    proc(x: Token): string =
      case x.type
      of LinkToken: x.linkVal.text
      of ImageToken: x.imageVal.alt
      else: renderToken(x)
  ).join("")

proc renderToken(token: Token): string =
  case token.type
  of ParagraphToken: p(token.renderInline)
  of LinkToken:
    if token.linkVal.title == "": a(
      href=token.linkVal.url.escapeBackslash.escapeLinkUrl,
      token.renderInline
    )
    else: a(
      href=token.linkVal.url.escapeBackslash.escapeLinkUrl,
      title=token.linkVal.title.escapeBackslash.escapeAmpersandSeq.escapeQuote,
      token.renderInline
    )
  of ImageToken:
    if token.imageVal.title == "": img(
      src=token.imageVal.url,
      alt=token.renderImageAlt
    )
    else: img(
      src=token.imageVal.url,
      alt=token.renderImageAlt,
      title=token.imageVal.title
    )
  of AutoLinkToken: a(href=token.autoLinkVal.url.escapeLinkUrl, token.autoLinkVal.text)
  of TextToken: token.textVal
  of EmphasisToken: em(token.renderInline)
  of StrongToken: strong(token.renderInline)
  of SoftLineBreakToken: token.softLineBreakVal
  of DummyToken: ""
  else: raise newException(MarkdownError, fmt"{token.type} rendering not impleted.")

proc renderState(state: State): string =
  var html: string
  for token in state.tokens.items:
    html = renderToken(token)
    if html != "":
      result &= html
      result &= "\n"

proc markdown*(doc: string): string =
  var tokens: DoublyLinkedList[Token]
  var state = State(doc: doc.strip, tokens: tokens, ruleSet: simpleRuleSet)
  state.tokens.append(Token(type: DummyToken, slice: (0..0), dummyVal: ""))
  parse(state)
  renderState(state)

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
  check getLinkLabelSlice("[a]", 0, slice) == 3; check slice == (0 .. 2)
  check getLinkLabelSlice("[[a]", 0, slice) == -1;
  check getLinkLabelSlice("[[a]", 1, slice) == 3; check slice == (1 .. 3)
  check getLinkLabelSlice("[[a]]", 0, slice) == 5; check slice == (0 .. 4)
  check getLinkLabelSlice("[a]]", 0, slice) == 3; check slice == (0 .. 2)
  check getLinkLabelSlice(r"[a\]]", 0, slice) == 5; check slice == (0 .. 4)
  check getLinkLabelSlice("[link]", 0, slice) == 6; check slice == (0 .. 5)
  check getLinkLabelSlice("[link [foo [bar]]]", 0, slice) == 18; check slice == (0 .. 17)
  check getLinkLabelSlice("[link] bar]", 0, slice) == 6; check slice == (0 .. 5)
  check getLinkLabelSlice("[link [bar]", 0, slice) == -1;
  check getLinkLabelSlice(r"[link \[bar]", 0, slice) == 12; check slice == (0 .. 11)
  check getLinkLabelSlice("[foo [bar](/uri)]", 0, slice) == 17; check slice == (0 .. 16)
  check getLinkLabelSlice("[foo *[bar [baz](/uri)](/uri)*]", 0, slice) == 31; check slice == (0 .. 30)
  check getLinkLabelSlice("![[[foo](uri1)](uri2)]", 1, slice) == 21; check slice == (1 .. 21)
  check getLinkLabelSlice("*[foo*]", 1, slice) == 6; check slice == (1 .. 6)

  
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

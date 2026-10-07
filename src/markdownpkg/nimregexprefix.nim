## Bounded prefix matching for nim-regex.
##
## nim-regex exposes an anchored matcher internally, but it does not expose an
## end offset. This is the minimal matching loop required by the markdown
## compatibility layer to preserve `std/re`'s `bufSize` behavior without
## copying the input prefix.

import std/[tables, unicode]

from pkg/regex/common import bwRuneAt
import pkg/regex/nfamatch2 as nfaMatch
import pkg/regex/nfatype
import pkg/regex/nodematch as nodeMatch
import pkg/regex/types as regexTypes

proc nextState(
    smA, smB: var Pstates,
    capts: var Capts3,
    look: var nfaMatch.Lookaround,
    text: string,
    nfa2: regexTypes.Nfa,
    index: int,
    previous: int32,
    character: Rune,
    flags: MatchFlags,
) {.inline.} =
  template nfa: untyped = nfa2.s
  template bounds2: untyped = bounds.a..index - 1
  template nextIndex: untyped = nfa[nodeIndex].next[transitionIndex]
  template nextNode: untyped = nfa[nextIndex]
  template nodeIndex: untyped = state.ni
  template captureIndex: untyped = state.ci
  template bounds: untyped = state.bounds

  let anchored = mfAnchored in flags
  var capture = 0.CaptIdx
  var matched = true
  smB.clear()
  for state in smA.items:
    if anchored and nfa[nodeIndex].kind == regexTypes.reEoe:
      if nodeIndex notin smB:
        smB.add(initPstate(nodeIndex, captureIndex, bounds))
      break
    let transitionCount = nfa[nodeIndex].next.len
    var transitionIndex = 0
    while transitionIndex < transitionCount:
      let nextNodeIndex = nextIndex
      matched = nextIndex notin smB and
        (nodeMatch.match(nextNode, character) or
          (anchored and nextNode.kind == regexTypes.reEoe))
      inc transitionIndex
      capture = captureIndex
      while transitionIndex < transitionCount and regexTypes.isEpsilonTransition(nextNode):
        if matched:
          nfaMatch.epsilonMatch(
            matched,
            capture,
            capts,
            look,
            nextNode,
            text,
            index,
            previous,
            character,
            flags,
          )
        inc transitionIndex
      if matched:
        smB.add(initPstate(nextNodeIndex, capture, bounds2))
  swap(smA, smB)
  if mfNoCaptures notin flags:
    for state in smA.items:
      if state.ci != -1:
        capts.keepAlive(state.ci)
    capts.recycle()

proc matchPrefix*(
    text: string,
    pattern: Regex2,
    matched: var RegexMatch2,
    start, limit: int,
): bool =
  ## Match `pattern` at `start`, treating `limit` as the end of the input.
  ##
  ## `start` and `limit` are byte offsets. The markdown adapter always uses
  ## `regexArbitraryBytes`, so a limit may fall between UTF-8 code points.
  if start < 0 or start > limit or limit > text.len:
    return

  let regex = pattern.toRegex
  matched.clear()
  let flags = regex.flags.toMatchFlags + {mfAnchored}
  var
    active = initPstates(regex.nfa.s.len)
    next = initPstates(regex.nfa.s.len)
    captures = initCapts3(regex.groupsCount)
    captureIndex = -1.CaptIdx
    look = nfaMatch.initLook()
    character = Rune(-1)
    previous = -1'i32
    index = start
    nextIndex = start

  if start - 1 in 0..text.len - 1:
    previous = if mfBytesInput in flags:
      text[start - 1].int32
    else:
      bwRuneAt(text, start - 1).int32

  active.add(initPstate(0'i16, captureIndex, index..index - 1))
  while index < limit:
    if mfBytesInput in flags:
      character = text[nextIndex].Rune
      inc nextIndex
    else:
      fastRuneAt(text, nextIndex, character, true)
    nextState(active, next, captures, look, text, regex.nfa, index, previous, character, flags)
    if active.len == 0:
      return false
    if regex.nfa.s[active[0].ni].kind == regexTypes.reEoe:
      break
    index = nextIndex
    previous = character.int32

  character = Rune(-1)
  nextState(active, next, captures, look, text, regex.nfa, index, previous, character, flags)
  result = active.len > 0
  if result:
    captureIndex = active[0].ci
    matched.captures.setLen(regex.groupsCount)
    if captureIndex != -1:
      for index in 0..<matched.captures.len:
        matched.captures[index] = captures[captureIndex, index]
    else:
      for index in 0..<matched.captures.len:
        matched.captures[index] = nonCapture
    if regex.namedGroups.len > 0:
      matched.namedGroups = regex.namedGroups
    matched.boundaries = active[0].bounds

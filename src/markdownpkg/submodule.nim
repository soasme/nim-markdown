# This is just an example to get you started. Users of your hybrid library will
# import this file by writing ``import markdownpkg/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

import re, strutils, strformat, tables, sequtils, math

type
    # Type for header element
    Header* = object
        doc: string
        level: int

    # Signify the token type
    MarkdownTokenType* {.pure.} = enum
        Header

    # Hold two values: type: MarkdownTokenType, and xyzValue.
    # xyz is the particular type name.
    MarkdownTokenRef* = ref MarkdownToken
    MarkdownToken* = object
        pos: int
        len: int
        case type*: MarkdownTokenType
        of MarkdownTokenType.Header: headerVal*: Header

var blockRules = @{
    MarkdownTokenType.Header: re"^ *(#{1,6}) *([^\n]+?) *#* *(?:\n+|$)"
}.newTable

# Replace `<` and `>` to HTML-safe characters.
# Example:
#   >>> escapeTag("<tag>")
#   "&lt;tag&gt;"
proc escapeTag*(doc: string): string =
    result = doc.replace("<", "&lt;")
    result = result.replace(">", "&gt;")

# Replace `'` and `"` to HTML-safe characters.
# Example:
#   >>> escapeTag("'tag'")
#   "&quote;tag&quote;"
proc escapeQuote*(doc: string): string =
    result = doc.replace("'", "&quote;")
    result = result.replace("\"", "&quote;")

# Replace character `&` to HTML-safe characters.
# Example:
#   >>> escapeAmpersandChar("&amp;")
#   &amp;amp;
proc escapeAmpersandChar*(doc: string): string =
    result = doc.replace("&", "&amp;")

let reAmpersandSeq = re"&(?!#?\w+;)"

# Replace `&` from a sequence of characters starting from it to HTML-safe characters.
# It's useful to keep those have been escaped.
# Example:
#   >>> escapeAmpersandSeq("&") # In this case, it's like `escapeAmpersandChar`.
#   "&"
#   >>> escapeAmpersandSeq("&amp;") # In this case, we preserve that has escaped.
#   "&amp;"
proc escapeAmpersandSeq*(doc: string): string =
    result = doc.replace(sub=reAmpersandSeq, by="&amp;")

# Find a markdown token from document `doc` at position `start`,
# based on a rule type and regex rule.
proc findToken(doc: string, start: int, ruleType: MarkdownTokenType, regex: Regex): MarkdownTokenRef =
    var matches: array[5, string]

    let size = doc.matchLen(regex, matches=matches, start=start)
    if size == -1:
        return nil

    case ruleType
    of MarkdownTokenType.Header:
        var val: Header
        val.level = matches[0].len
        val.doc = matches[1]
        result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.Header, headerVal: val)  

# Parse markdown document into a sequence of tokens.
iterator parseTokens(doc: string): MarkdownTokenRef =
    var n = 0
    while n < doc.len:
        for ruleType, ruleRegex in blockRules:
            let token = findToken(doc, n, ruleType, ruleRegex)
            if token != nil:
                n += token.len
                yield token
                break


# Render header tag, for example, `<h1>`, `<h2>`, etc.
# Example:
#   >>> renderHeader("hello world", level=1)
#   "<h1>hello world</h1>"
proc renderHeader*(header: Header): string =
    result = fmt"<h{header.level}>{header.doc}</h{header.level}>"

proc renderToken(token: MarkdownTokenRef): string =
    case token.type
    of MarkdownTokenType.Header:
        result = renderHeader(token.headerVal)

# Turn markdown-formatted string into HTML-formatting string.
# By setting `escapse` to false, no HTML tag will be escaped.
proc markdown*(doc: string,
        escape: bool = true): string =
    for token in parseTokens(doc):
        result &= renderToken(token)
# This is just an example to get you started. Users of your hybrid library will
# import this file by writing ``import markdownpkg/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

import re, strutils


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

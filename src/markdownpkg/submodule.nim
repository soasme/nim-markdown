# This is just an example to get you started. Users of your hybrid library will
# import this file by writing ``import markdownpkg/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

import re, strutils


# Replaces `<` and `>` to HTML-safe characters.
proc escapeTag*(doc: string): string =
    result = doc.replace("<", "&lt;")
    result = result.replace(">", "&gt;")

# Replaces `'` and `"` to HTML-safe characters.
proc escapeQuote*(doc: string): string =
    result = doc.replace("'", "&quote;")
    result = result.replace("\"", "&quote;")

# Replace `&` to HTML-safe characters.
proc escapeAmpersand*(doc: string): string =
    result = doc.replace("&", "&amp;")


proc getWelcomeMessage*(): string = "Hello, World!"

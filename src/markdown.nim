# This is just an example to get you started. A typical hybrid package
# uses this file as the main entry point of the application.

import markdownpkg/markdown

when isMainModule:
  stdout.write(markdown(stdin.readAll))

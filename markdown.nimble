# Package

version       = "0.8.8"
author        = "Ju Lin"
description   = "A Markdown Parser in Nim World."
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["markdown"]


# Dependencies

requires "nim >= 0.19.0"

feature "regex":
  ## Use nim-regex instead of `std/re` to avoid the PCRE1 runtime dependency.
  requires "regex >= 0.26.3"

task watch, "run test cases whenever modified the code.":
  exec "watchmedo shell-command --patterns='*.nim' --recursive --command='nimble test' ."

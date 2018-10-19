# Nim-markdown

`nim-markdown` is a beautiful Markdown Parser in the Nim world.

[![Donate to this project using Patreon](https://img.shields.io/badge/patreon-donate-green.svg?style=for-the-badge&colorB=green)](https://patreon.com/enqueuezero)
[![Documentation](https://img.shields.io/badge/documentation-passed-brightgreen.svg?style=for-the-badge&longCache=true)](https://www.soasme.com/nim-markdown/markdown.html)

## Install

Work in progress. :)

```bash
$ nimble install markdown # won't work now.
```

The package is in review. [nim-lang/packages#899](https://github.com/nim-lang/packages/pull/899).

## Library Usage

The basic usage of library `markdown` is comprised of a three-step. Example minimal code is like below.

```nim
# 1. import pkg.
import markdown

# 2. transform md to html.
let html = markdown("# Hello World\nHappy writing Markdown document!")

# 3. do something :)
echo(html)
```

## Binary Usage

The basic usage of binary `markdown is like below:

```
# Read from stdin and write to stdout.
$ markdown < hello-world.md > hello-world.html
```

## Development

Build markdown binary:

```
$ nimble build
```

Test markdown modules:

```
$ nimble test
```

The [Markdown Parser](https://enqueuezero.com/drafts/markdown-parser.html) serves as a guidance on the implementation of `nim-markdown`, or in any generic programming language.

## Roadmap

Priorities (WIP for top to bottom):

* Feature complete and correctness.
* Documentation & tutorial.
* Support controlling options, for example, escaping, text wrapping, html sanitize, etc.
* Refactor the codebase in a extension friendly way.
* Benchmark.
* Support converting from HTML to Markdown.

## ChangeLog

Released:

* v0.1.2, TBD, add parameter `config` to proc `markdown` & support `[url](<text> "title")`.
* v0.1.1, 18 Oct 2018, import from `markdown` instead `markdownpkg/core`.
* v0.1.0, 17 Oct 2018, initial release.

## License

Nim-markdown is based on MIT license.
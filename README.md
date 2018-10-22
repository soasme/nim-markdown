# Nim-markdown

`nim-markdown` is a beautiful Markdown Parser in the Nim world.

[![Donate to this project using Patreon](https://img.shields.io/badge/patreon-donate-green.svg?style=for-the-badge&colorB=green)](https://patreon.com/enqueuezero)
[![Documentation](https://img.shields.io/badge/documentation-passed-brightgreen.svg?style=for-the-badge&longCache=true)](https://www.soasme.com/nim-markdown/markdown.html)
[![Build Status](https://travis-ci.org/soasme/nim-markdown.svg?branch=master)](https://travis-ci.org/soasme/nim-markdown)

## Install

Install via `nimble` in your project root.

```bash
$ nimble install markdown

# or with current stable version
$ nimble install markdown@">= 0.2.0"

# or with the latest version
$ nimble install markdown@#head
```

Or simply copy paste `src/markdown.nim` into your project.

## Library Usage

Below is the minimal usage of using `markdown` as a library.

```nim
# 1. import pkg.
import markdown

# 2. transform md to html.
let html = markdown("# Hello World\nHappy writing Markdown document!")

# 3. do something :)
echo(html)
```

Below are some useful links:

* The API documentation: <https://www.soasme.com/nim-markdown/markdown.html>
* The dev guide: <https://enqueuezero.com/markdown-parser.html>
* The cheat sheet: <https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet>

## Binary Usage

The usage of binary `markdown is like below:

```
# Read from stdin and write to stdout.
$ markdown < hello-world.md > hello-world.html
```

## Development

Build markdown binary:

```bash
$ nimble build
```

Test markdown modules:

```bash
$ nimble test
```

Test markdown modules incrementally whenever modified the code. It requires you to have `watchdog` installed.

```bash
$ nimble watch
```

The [Markdown Parser](https://enqueuezero.com/markdown-parser.html) serves as a guidance on the implementation of `nim-markdown`, or in any generic programming language.

## Roadmap

Priorities:

* WIP: Provide a correct implementation of GitHub Flavored Markdown Specification, or notably referred to as [GFM](https://github.github.com/gfm/). (#4)
* Support more controlling options, for example, escaping, text wrapping, html sanitize, etc.
* Write tutorial & document on how to extend this library.
* Support converting from HTML to Markdown. (#1)
* Benchmark.

Features:

- [x] Header
- [x] GFM 4.1 Thematic Break
- [x] Indented code block
- [x] Fence code block
- [x] Blockquote
- [x] Ordered/Un-ordered List
- [x] Nested lists
- [x] Raw HTML block
- [x] Table
- [x] Footnote
- [x] Ref Link
- [x] Inline Link
- [x] Auto link
- [x] Image Link
- [x] Emphasis
- [x] Double Emphasis
- [x] Strikethrough
- [x] Link Break
- [x] Inline Code
- [x] Inline HTML
- [x] Escape
- [x] Paragraph
- [ ] Want new features? Issues or pull requests are welcome. ;)

## ChangeLog

Released:

* v0.3.1, 22 Oct 2018, bugfix: soft line breaks (gfm 6.13).
* v0.3.0, 22 Oct 2018, support html table block (#3).
* v0.2.0, 20 Oct 2018, package published [nim-lang/packages#899](https://github.com/nim-lang/packages/pull/899).
* v0.1.2, 19 Oct 2018, add parameter `config` to proc `markdown` & support `[url](<text> "title")`.
* v0.1.1, 18 Oct 2018, import from `markdown` instead `markdownpkg/core`.
* v0.1.0, 17 Oct 2018, initial release.

## License

Nim-markdown is based on MIT license.

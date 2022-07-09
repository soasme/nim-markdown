# Nim-markdown

`nim-markdown` is a Markdown Parser in the Nim world.

[![Documentation](https://img.shields.io/badge/documentation-passed-brightgreen.svg?style=for-the-badge&longCache=true)](https://www.soasme.com/nim-markdown/)
[![Build Status](https://travis-ci.org/soasme/nim-markdown.svg?branch=master)](https://travis-ci.org/soasme/nim-markdown)

## Install

Install via `nimble` in your project root.

```bash
$ nimble install markdown

# or with current stable version
$ nimble install markdown@">= 0.8.0"

# or with the latest version
$ nimble install markdown@#head
```

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

* The API documentation: <https://www.soasme.com/nim-markdown/htmldocs/markdown.html>
* The dev guide: <https://enqueuezero.com/markdown-parser.html>
* The cheat sheet: <https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet>

## Binary Usage

The usage of binary `markdown` is as below:

```
# Read from stdin and write to stdout.
$ markdown < README.md > README.html
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

Build document:

```bash
$ nim doc --project --git.url=https://github.com/soasme/nim-markdown --git.commit=v0.7.0 src/markdown.nim
```

The [Markdown Parser](https://enqueuezero.com/markdown-parser.html) serves as a guidance on the implementation of `nim-markdown`, or in any generic programming language.

## Roadmap

Priorities:

* [x] Support Commonmark.
* [ ] Support GFM.
* [ ] Support writing extensions.
* [ ] Benchmark.

Features:

- [x] Thematic Break
- [x] Heading
- [x] Indented code block
- [x] Fence code block
- [x] Block Quote
- [x] Ordered/Unordered List
- [x] Nested lists
- [x] Raw HTML block
- [x] Table
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
- [ ] Auto link (extension)
- [ ] Footnote
- [ ] Want new features? Issues or pull requests are welcome. ;)

## ChangeLog

Released:

* v0.8.6, 9 Jul 2022, bugfix: export no internal procs.
* v0.8.5, 19 Mar 2021, bugfix: codespan might be empty. #42.
* v0.8.4, 19 Mar 2021, performance improvement: eliminate all `firstLine` and `restLines` calls. (#54, #55, #56).
* v0.8.3, 13 Mar 2021, performance improvement: faster html pattern matching (#52) & eliminate all `since()` calls (#53).
* v0.8.2, 3 Mar 2021, performance improvement: use pre-compiled regex.
* v0.8.1, 30 Dec 2019, bugfix: fixed compatibility with `--gc:arc`.
* v0.8.0, 8 Sep 2019, bugfix: gcsafe with nim `--threads:on`.
* v0.7.2, 8 Sep 2019, rename internal package to markdownpkg.
* v0.7.1, 7 Sep 2019, removed useless constants.
* v0.7.0, 6 Sep 2019, support parsing in commonmark [v0.29](https://spec.commonmark.org/0.29/) syntax.
* v0.5.4, 1 Aug 2019, bugfix: improved the ul & ol parsing.
* v0.5.3, 3 Jun 2019, bugfix: Added import exceptions for strip and splitWhitespace from unicode [#20](https://github.com/soasme/nim-markdown/issues/20).
* v0.5.2, 5 Nov 2018, bugfix: ambiguous call.
* v0.5.1, 4 Nov 2018, inline email support; bugfix: \u00a0 causing build error [#16](https://github.com/soasme/nim-markdown/issues/16), etc.
* v0.5.0, 3 Nov 2018, bugfix: links in lists not working (#14), etc.
* v0.4.0, 27 Oct 2018, support `~~~` as fence mark, etc. [#12](https://github.com/soasme/nim-markdown/pull/12).
* v0.3.4, 24 Oct 2018, support hard line breaks (gfm 6.12).
* v0.3.3, 23 Oct 2018, strict-typed config (#5), add cli options.
* v0.3.2, 23 Oct 2018, support setext heading.
* v0.3.1, 22 Oct 2018, bugfix: soft line breaks (gfm 6.13).
* v0.3.0, 22 Oct 2018, support html table block (#3).
* v0.2.0, 20 Oct 2018, package published [nim-lang/packages#899](https://github.com/nim-lang/packages/pull/899).
* v0.1.2, 19 Oct 2018, add parameter `config` to proc `markdown` & support `[url](<text> "title")`.
* v0.1.1, 18 Oct 2018, import from `markdown` instead `markdownpkg/core`.
* v0.1.0, 17 Oct 2018, initial release.

## License

Nim-markdown is based on MIT license.

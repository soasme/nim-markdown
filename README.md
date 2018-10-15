# nim-markdown

`nim-markdown` is a Markdown Parser in Nim programming language.

## Install

Work in progress. :)

```bash
$ nimble install markdown # won't work now.
```

## Library Usage

The basic usage of library `markdown` is comprised of a three-step. Example minimal code is like below.

```nim
# 1. import pkg.
import markdownpkg/core

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

Run below command to test markdown modules:

```
$ nimble test
```

## License

nim-markdown is based on MIT license.

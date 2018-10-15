# nim-markdown

`nim-markdown` is a Markdown Parser in Nim programming language.

## Install

```bash
$ nimble install markdown
```

## Library Usage

The basic usage of library `markdown` is comprised of a three-step:

* Import package `markdownpkg/core`.
* Call `markdown` function.
* Do whatever you want!

Example nim code is like below.

```nim
# import pkg.
import markdownpkg/core

# transform md to html.
let html = markdown("# Hello World\nHappy writing Markdown document!")

# do something :)
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

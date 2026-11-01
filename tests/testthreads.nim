# Regression test for https://github.com/soasme/nim-markdown/issues/76:
# calling `markdown()` from several threads at once must not crash.

import unittest
import markdown

const
  ThreadCount = 8
  Iterations = 200
  Doc = """
# Heading

Some *emphasis*, **strong**, `code` & an [link](http://example.com "t").

<div>html block</div>

- item 1
- item 2

> quote

| a | b |
|---|---|
| 1 | 2 |
"""

proc render(): string =
  {.cast(gcsafe).}:
    result = markdown(Doc, config=initGfmConfig())

let expected = render()

proc worker(ok: ptr bool) {.thread.} =
  var same = true
  for i in 0 ..< Iterations:
    {.cast(gcsafe).}:
      if render() != expected:
        same = false
  ok[] = same

test "markdown is safe to call from multiple threads":
  var threads: array[ThreadCount, Thread[ptr bool]]
  var results: array[ThreadCount, bool]
  for i in 0 ..< ThreadCount:
    createThread(threads[i], worker, addr results[i])
  joinThreads(threads)
  for ok in results:
    check ok

## Compare the steady-state parsing performance of the configured regex backend.
##
## Build this file once with the default configuration and once with
## `-d:feature.markdown.regex`, then run both binaries with the same arguments.

import std/[algorithm, monotimes, os, parseutils, strformat, times]

import markdown

const backend =
  when defined(feature.markdown.regex) or defined(`feature.nim-markdown.regex`):
    "nim-regex"
  else:
    "pcre"

proc usage() =
  quit "usage: backend_benchmark ROUNDS FILE [FILE ...]"

proc elapsedMilliseconds(started: MonoTime): float =
  let elapsed = getMonoTime() - started
  elapsed.inNanoseconds.float / 1_000_000.0

proc fnv1a(text: string): uint64 =
  result = 14_695_981_039_346_656_037'u64
  for character in text:
    result = result xor character.uint64
    result = result * 1_099_511_628_211'u64

proc collectGarbage() =
  when declared(GC_fullCollect):
    GC_fullCollect()

proc parseTimed(input: string): tuple[elapsedMs: float, output: string] =
  collectGarbage()
  let started = getMonoTime()
  result.output = markdown(input)
  result.elapsedMs = elapsedMilliseconds(started)

proc median(sortedSamples: openArray[float]): float =
  let middle = sortedSamples.len div 2
  if sortedSamples.len mod 2 == 0:
    (sortedSamples[middle - 1] + sortedSamples[middle]) / 2.0
  else:
    sortedSamples[middle]

proc benchmark(path: string, rounds: Natural) =
  let input = readFile(path)

  let cold = parseTimed(input)
  let expectedLength = cold.output.len
  let expectedHash = fnv1a(cold.output)
  echo &"backend={backend}\tfile={path.extractFilename}\tbytes={input.len}" &
    &"\tphase=cold\tms={cold.elapsedMs:.3f}\thtmlBytes={expectedLength}" &
    &"\thash={expectedHash}"

  if rounds == 0:
    return

  var samples = newSeqOfCap[float](rounds)
  for _ in 1 .. rounds:
    let sample = parseTimed(input)
    doAssert sample.output.len == expectedLength
    doAssert fnv1a(sample.output) == expectedHash
    samples.add sample.elapsedMs

  samples.sort()
  var total = 0.0
  for sample in samples:
    total += sample
  echo &"backend={backend}\tfile={path.extractFilename}\tbytes={input.len}" &
    &"\tphase=warm\trounds={rounds}\tminMs={samples[0]:.3f}" &
    &"\tmedianMs={samples.median:.3f}\tmeanMs={total / samples.len.float:.3f}" &
    &"\tmaxMs={samples[^1]:.3f}\thtmlBytes={expectedLength}\thash={expectedHash}"

let arguments = commandLineParams()
if arguments.len < 2:
  usage()

var rounds = 0
if parseInt(arguments[0], rounds) != arguments[0].len or rounds < 0:
  usage()

for index in 1 ..< arguments.len:
  benchmark(arguments[index], rounds)

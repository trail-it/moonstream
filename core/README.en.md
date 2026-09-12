# MoonStream

> Field-level incremental parsing and completeness contracts for LLM streaming structured output,
> for the MoonBit ecosystem.

Tool-call arguments streamed by a model are JSON that is *never quite finished*. MoonStream consumes
the argument fragment bytes you already extracted from your SDK, keeps syntax state across fragments,
and delivers **structural events**, **completed leaf values**, and **a completeness verdict** — without
connecting to a model, and without pretending a preview is the final result.

Version: **0.1.0**. [Source repository](https://github.com/trail-it/moonstream).
The normative specification is in [docs/semantics.md](docs/semantics.md) (Chinese).

## What it solves

Existing SDKs (`mizchi/llm`, `DC-Z-lab/moonllm`, `marianoguerra/llm-mb`) deliver tool arguments as text
deltas, or ask consumers to wait for stream completion. Every application then has to handle half a
string, half a number, unclosed objects, UTF-8 code points split across chunks, and truncated streams.

MoonStream makes that layer a reusable, independent capability:

- **Fields usable as they close**: keys and completed leaf values arrive as events before the stream ends.
- **No guessing**: `{"count":1` is not delivered as the number `1`, because `2`, `.5` or `e2` may follow.
- **A clear delivery boundary**: only the `CompletedDocument` returned by `finish(EndOfStream)` means the
  whole document is valid.
- **Chunk independence**: any way of splitting the same input yields the same document and the same
  normalized event sequence.

## Quick start

```bash
# Run from the repository root
moon run --target native examples/consumer
# Install in your own project: moon add trail-it/moonstream
```

```mbt
let parser = Parser::new()
let first = parser.feed(b"{\"city\":\"上")   // ObjectBegin, KeyComplete, StringDelta
let second = parser.feed(b"海\",\"count\":12}")
let (tail_events, result) = parser.finish()
match result {
  FinishResult::Completed(doc) => use(doc.to_string())
  FinishResult::Incomplete(pos~, expected~) => report_incomplete(pos, expected)
  FinishResult::Aborted(reason~) => discard(reason)
}
```

`finish` terminates the parser, including when it returns `Incomplete`. Collect remaining input before finishing, or replay retained fragments into a new parser.

Compile-checked versions of the README examples live in [README.mbt.md](README.mbt.md).

## Core concepts

| Type | Meaning |
|---|---|
| `Parser` | Incremental parser for one JSON document: `feed(Bytes)`, `finish(EndReason)` |
| `Event` | `ObjectBegin/End`, `ArrayBegin/End`, `KeyComplete`, `StringDelta`, `ValueComplete` |
| `Path` | Position such as `$.items[0].name`; it describes location, not validity |
| `Span` | Absolute byte range, independent of chunking |
| `NumberLiteral` | Original number lexeme, so large integers are not silently rounded |
| `CompletedDocument` | Opaque, parser-constructed; the document is valid under strict syntax policy |
| `Limits` | Depth / per-token bytes / node count / total input caps |

## Guarantees

- A leaf value confirmed by a syntactic boundary will not change in a final valid document.
- Any chunking yields the same final document, the same error position, and an equivalent **normalized**
  event sequence (adjacent same-path `StringDelta`s merged).
- Concatenated `StringDelta`s for one string exactly cover that string's text.
- Only `EndOfStream` can produce a `CompletedDocument`; cancellation and truncation return `Aborted`.

Not guaranteed: monotonicity of all preview nodes; that a completed subtree makes the document valid;
repair of arbitrarily broken JSON; prompt-injection or denial-of-service protection.

## Preview and multi-call routing

`@preview.Preview` projects the event stream onto a partial tree for frame-by-frame UI rendering. Its
`NodeState` keeps four "no value yet" cases apart: `Missing`, `Pending` (key known, value not usable yet),
`IncompleteString(text)`, and `Complete(value)` — where `Complete(LeafValue::Null)` is a real JSON null.
There is deliberately no public constructor that turns a partial tree into a `CompletedDocument`.

`@session.Session` routes fragments of several tool calls to independent parsers keyed by
`(response, choice, index)`. Feeding an unopened call raises `UnknownCall`; conflicting ids or names raise
`CallIdConflict` / `CallNameConflict`; a parse failure in one call is reported as `ParseFailed` and leaves
the other calls untouched. Cancelling one call never affects the others.

Real SDK adapters live in the repository's [`adapters/`](../adapters/) directory as separate workspace
modules (`trail-it/llm_mb_adapter`, `trail-it/mizchi_llm_adapter`, `trail-it/moonllm_adapter`), so the
core library itself depends on **no** LLM SDK.

## Differences from RFC 8259

MoonStream uses RFC 8259 JSON grammar and is **stricter** in these explicit policies: duplicate keys are
rejected, lone surrogates in `\u` escapes are rejected, UTF-8 is fully validated (overlong encodings,
surrogate code points and code points above U+10FFFF are rejected), and non-whitespace after the root
value is `TrailingContent`.

## Testing and backends

```bash
moon check --deny-warn --target all
moon test --target wasm-gc && moon test --target js && moon test --target native
moon fmt && moon info
```

Coverage: full grammar, chunk invariance (exhaustive single split points, seeded multi-chunk, byte by
byte), prefix behavior against an independent oracle, negative controls, Unicode and surrogate pairs,
number lexemes and precision, limit boundaries, and parser lifecycle.

## Offline replay tool

```bash
moon run --target native cmd/replay                 # built-in sample
moon run --target native cmd/replay -- '[1,2' 2     # truncated stream
moon run --target native cmd/replay -- '01' 1       # leading-zero error
```

## Relationship to neighbouring projects

MoonStream consumes argument fragments that protocol SDKs already extracted (`mizchi/llm`,
`DC-Z-lab/moonllm`, `marianoguerra/llm-mb`); it is not `jsonl` (complete records per line), not `jsonx`
(readers over already-parsed `Json`), and it does not reimplement schema validators such as
`moon_zod` or `moonschema` — it feeds them after parsing.

## Roadmap

- **M1 (done)**: byte-incremental lexer and grammar stack, completeness model, chunk-invariance tests,
  replay tool.
- **M2**: `Preview` partial-tree projection, `Session` multi-tool-call routing, two real SDK adapters.
- **M3**: three-backend CI, complexity and memory report, bilingual docs, browser wasm-gc demo.
- **M4**: ecosystem feedback, API convergence, maintenance plan.

## License

Apache-2.0. See [LICENSE](LICENSE).

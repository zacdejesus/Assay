# 0005: Cassette (record and replay)

- **Status:** Accepted (2026-11-16). Drafted by Claude from Experiment D. Alejandro chose the
  three open questions of roadmap M2 (one file per test, match by request, greedy by default).
- **Context docs:** [roadmap M2](../roadmap.md), [notes/foundationmodels.md](../notes/foundationmodels.md),
  [0003: FakeModel public API](0003-fakemodel-api.md)
- **Code:** `Sources/Assay/Cassette.swift`, `CassetteRequest.swift`, `Tape.swift`;
  `Tests/AssayTests/CassetteTests.swift`, `RecordedTapeTests.swift`

## Context

M2 records what the real model answers, keeps it in a file, and replays it on any machine. M0
left a problem: an executor can forward the real model but can't read what it says (the
channel's events are opaque), while a session can read everything but isn't something a test's
code under test hands over. Recording and replay seemed to need different APIs.

## Experiment D (macOS 27.2, 2026-11-16)

A one-off script. A custom model whose executor, instead of forwarding the channel, runs the
request again in a **session of its own** over the real model: a transcript with every entry
but the last prompt, then `respond(to:)` with that prompt, the request's schema and options.

| Question | Answer |
|---|---|
| Can an executor run a nested session over the real model? | **Yes.** No deadlock, no error. |
| Is the answer the same as asking the real model directly (greedy)? | **Yes**, for plain text, for a session with instructions and two turns, and for structured output. |
| Does structured output survive being sent back as JSON text? | **Yes.** The outer session decodes it into the `@Generable` type. |
| Is `Transcript` Codable? | **Yes**, and it round-trips. But every entry has a generated ID, so it can't be a key as it is. |
| Is an encoded `GenerationSchema` stable? | **No.** Two encodings of the same schema differ in key order. It needs canonical JSON, like `GeneratedContent.jsonString`. |

So one executor does both jobs, and the request key is computed in one place for both.

## Decision

A `Cassette` owns a tape file and vends a `LanguageModel`:

```swift
let cassette = try Cassette("capital")
let session = LanguageModelSession(model: cassette.model)
```

| Question | Choice |
|---|---|
| One file per test or per interaction? | **Per cassette name**, which in practice is per test: `__Cassettes__/<name>.json` next to the test file. One readable diff. |
| Match by key or replay in order? | **By key.** A request is answered only by a recording of the same request. Anything else fails and shows the closest recording and which parts differ. |
| What is "the same request"? | Instructions, earlier turns, prompt, schema and options, as canonical JSON, hashed with SHA-256. The framework's generated IDs are left out. |
| The same request twice? | Recorded twice. Replayed in recorded order; the last answer repeats. |
| Sampling while recording? | **Greedy unless the test chose a mode** (Experiment C: greedy is repeatable). The request keeps what the test asked for; the provenance says what was used. |
| Modes | `.replay`, `.record`, `.auto` (replay if the tape exists, else record). `ASSAY_CASSETTE` decides for cassettes in `.auto`; a mode chosen in code is kept. **With `CI` set, nothing records.** |
| Does replay ever call the model? | **Never.** |
| How is the answer sent back? | In one piece, with the recorded token count, through the same line of code when recording and when replaying, so a test behaves the same in both. |
| Structured output in the file | Nested JSON, not an escaped string, so a tape's diff is readable. Sent back as canonical JSON. |

**Provenance**, per interaction: `assetIDs` (sorted), the model's `systemVersion`, the sampling
used, and the date. Per tape: format version, Assay version, hardware model.

**Hooks:** `normalize` changes a request before it is matched and stored (dates, IDs);
`redact` changes a response before it is stored.

**Replay is not a `FakeModel`.** Decision 0003 expected replay to be "a `FakeModel` fed from a
tape". Recording turned out to live in the executor too, and `.auto` needs one model type that
does either, so `Cassette.Model` has its own executor. The two share the design (a reference
box in the configuration), not the code.

## Not in format v1

- Tools, tool calls, reasoning entries and attachments: the request throws
  `CassetteError.unsupported`, rather than recording something that would replay differently.
- Errors: a call that throws while recording isn't stored.
- Streaming shape: a replayed answer arrives in one piece. While recording, too.
- A Swift Testing trait (`@Test(.cassette("name"))`). The plain initializer came first.
- Recording only the missing interactions of an existing tape. `record` rewrites all of it.

## Consequences

- ➕ The code under test only needs a `LanguageModel`; it doesn't know about tapes.
- ➕ A tape holds the full request, so M4 can send the same requests to a newer model.
- ➖ While recording, the request reaches the model through a second session. Experiment D
  found no difference in the answers; nothing guarantees that for every future feature.
- ➖ Greedy by default means a recorded answer isn't what a user with default sampling would
  see. It is what the model considers most likely.
- ➖ The hardware model of the recording machine is written into the tape.

# Assay 🧪

[![Tests](https://github.com/zacdejesus/Assay/actions/workflows/tests.yml/badge.svg)](https://github.com/zacdejesus/Assay/actions/workflows/tests.yml)

**The memory and regression detector for Apple's language models.**

Apple updates its on-device model without asking you, and only one version lives on a device
at a time. If your AI feature gets worse after an update, the old behaviour is gone, unless
someone recorded it.

Assay records what the model answered, replays it offline, and tells you what changed.

> 🚧 **Status: early.** The M0 spike is done and its findings are below. M1 is in progress:
> `FakeModel`, `AvailabilityScript`, an [example app](#example-app) and a first version of
> [`Cassette`](#cassette) exist; the drift report doesn't yet.

## The problem

You ship a feature built on Apple's `FoundationModels`. Then:

- **The model changes under you.** Apple ships new model assets with its updates, and the assets
  carry their own version numbers, separate from the OS build (see
  [what M0 found](#what-m0-found)). Nothing tells you that your prompts now behave differently.
- **Tests that call the real model are slow and non-deterministic**, and they only run on a
  machine with Apple Intelligence.
- **Apple's `Evaluations` framework needs a live model**, so the same limits apply to your evals.

## The design

- **Cassettes.** Record the real model's answers once, with provenance (OS build, model asset
  IDs, generation options). Commit the tape. Replay it deterministically anywhere.
- **Drift report.** After a model update, re-run the suite live and compare it with the last
  recording: "37 unchanged, 3 flipped to fail, 1 flipped to pass", with diffs.
- **On top of Apple's frameworks, not instead of them.** Assay builds on the `LanguageModel`
  protocol (OS 27) and feeds Apple's `Evaluations`. It doesn't bring its own provider
  abstraction, matchers or judge.

The reasoning is in [docs/decisions/0001-positioning.md](docs/decisions/0001-positioning.md).

## What M0 found

M0 was a gate: could the plan work at all with public API? Three answers, all with tests or
SDK evidence in [docs/notes/foundationmodels.md](docs/notes/foundationmodels.md).

1. **A fake model can back a real session.** A custom `LanguageModel` drives a real
   `LanguageModelSession` in a plain unit test, in about a millisecond. That is the replay
   engine.
2. **You can wrap the real model, but you can't read it there.** A custom executor can
   forward to `SystemLanguageModel`'s executor, but the events it streams are opaque. So
   recording happens at the session level, from `session.transcript`, and replay happens at
   the executor level.
3. **The model has its own version, separate from the OS.** `Transcript.Response.assetIDs`
   names the model assets that produced an answer, and they carry their own version numbers.
   Provenance has to store those, not only the OS build.

The experiments stay in the repo as characterization tests: if a new OS changes the behaviour
Assay depends on, the failing test names the assumption that broke.

## FakeModel

A scripted model that backs a real `LanguageModelSession`, for unit tests that run in
milliseconds without Apple Intelligence.

```swift
import Assay

let model = FakeModel("Boil water.", "Add pasta.")
let session = LanguageModelSession(model: model)

let first = try await session.respond(to: "Step one?")   // "Boil water."

#expect(model.calls.count == 1)
#expect(model.calls[0].prompt == "Step one?")
```

Responses are used once each, in order; a call after the last one fails with a message that
says so. It also scripts JSON for `@Generable` types, errors and latency. Design notes:
[docs/decisions/0003-fakemodel-api.md](docs/decisions/0003-fakemodel-api.md).

## AvailabilityScript

Tests the screens an app shows when the model can't be used. The app reads availability through
a closure of its own, written with Apple's type, so Assay never ships in the app:

```swift
// App
var availability: () -> SystemLanguageModel.Availability = {
    SystemLanguageModel.default.availability
}

// Test
let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
viewModel.availability = script.next
// First read: still downloading. Every read after that: available.
```

Design notes:
[docs/decisions/0004-availability-simulation.md](docs/decisions/0004-availability-simulation.md).

## Cassette

Records what the real model answers into a file next to the test, and replays it from there:
no model, no Apple Intelligence, the same answer every time, in CI too.

```swift
@Test func capital() async throws {
    let cassette = try Cassette("capital")
    let session = LanguageModelSession(model: cassette.model)

    let response = try await session.respond(to: "What is the capital of France?")
    #expect(response.content.contains("Paris"))
}
```

- **First run:** calls the model and writes `__Cassettes__/capital.json`. Commit it.
- **Every run after:** reads the file. A request that isn't on the tape fails and shows the
  closest recording; replay never falls back to the model.
- **Record again:** `ASSAY_CASSETTE=record swift test`. In CI nothing is ever recorded.
- **Provenance:** each answer is stored with the model assets and system version that
  produced it. A tape is a snapshot of one model, and says which.

In `Package.swift`, add `exclude: ["__Cassettes__"]` to the test target. Not stored yet: tools,
attachments and streaming shape. Design notes:
[docs/decisions/0005-cassette.md](docs/decisions/0005-cassette.md).

## Apple's Evaluations, in CI

Apple's `Evaluations` framework needs a live model, for the answers and for a model judge.
Both accept a cassette's model, so an evaluation recorded on a Mac runs in CI from tapes, in
about a hundredth of a second:

```swift
let subject = try Cassette("evaluation-capitals")
let judge = try Cassette("evaluation-capitals-judge")
let result = try await CapitalsEvaluation(model: subject.model, judge: judge.model).run()
```

Guide: [docs/guides/evaluations-in-ci.md](docs/guides/evaluations-in-ci.md).

## Drift report

After an OS update, ask the new model everything the tapes hold and see what changed:

```sh
swift run assay drift Tests/MyTests/__Cassettes__ --report drift.md
```

```
**41 cases: 37 unchanged, 1 changed, 3 flipped to fail.**
```

With a pass criterion, from a test:

```swift
let report = try await Drift.check(tape: cassette.url) { request, answer in
    answer.contains("Paris")
}
#expect(report.count(.flippedToFail) == 0, "\(report.markdown())")
```

The report shows the before and after of every case that isn't unchanged, and says whether
the model assets actually differ. `--update` keeps the new answers and moves the old tape to
`generations/`. Design notes: [docs/decisions/0006-drift.md](docs/decisions/0006-drift.md).

So far it has only been run against the same model that recorded the tapes (9 of 9
unchanged). It hasn't seen a real model change yet.

## Example app

[Examples/TokenSpeed](Examples/TokenSpeed): an iOS and macOS app that shows how many tokens
per second the on-device model generates, with a fallback screen when the model can't be used.
The app doesn't import Assay; its tests do, and they run in a tenth of a second without
Apple Intelligence.

## Roadmap

| Milestone | What | Status |
|---|---|---|
| M0 | Spike: can I plug into Apple's protocol at all? | ✅ done |
| M1 | `FakeModel` and availability simulation (v0.1) | ✅ done |
| M2 | Cassette: record once, replay with provenance (v0.2) | in progress: text and structured output work |
| M3 | Bridge to Apple's `Evaluations`, offline (v0.3) | in progress: an evaluation with a judge runs from tapes |
| M4 | Drift report (v0.4) | in progress: works, not yet run across a real model change |
| M5 | Neutral comparison: on-device, Private Cloud Compute, cloud models (v0.5) | |

Details, risks and "done when" for each: [docs/roadmap.md](docs/roadmap.md).
Who else works in this space: [docs/prior-art.md](docs/prior-art.md).

## Run the experiments

Needs macOS 27 and Xcode 27.

```sh
scripts/test.sh          # unit tests: fake model, no live model used
scripts/test.sh live     # everything, including the tests that call the real model
scripts/test.sh greedy   # Experiment C: is greedy sampling repeatable?
```

The live modes need Apple Intelligence. All modes, and what to do before and after an OS
update, are in [docs/notes/environment.md](docs/notes/environment.md).

## What Assay is not

- Not a provider abstraction. That is Apple's `LanguageModel` protocol.
- Not matchers, an LLM judge or an eval runner. That is Apple's `Evaluations`.
- Not a hosted dashboard or a prompt manager.

## How this is built

I make the design decisions and review every line. AI assistance is used for spikes,
implementation and documentation; the decisions and their reasons are written down in
[docs/decisions](docs/decisions).

## License

[MIT](LICENSE).

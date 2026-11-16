# 0003: FakeModel public API

- **Status:** Accepted (2026-11-15). Drafted by Claude from a throwaway spike; the four API
  choices below were made by Alejandro.
- **Context docs:** [roadmap M1](../roadmap.md), [notes/foundationmodels.md](../notes/foundationmodels.md)
- **Code:** `Sources/Assay/FakeModel.swift`, `Tests/AssayTests/FakeModelTests.swift`

## Context

M1 needs a scripted `LanguageModel` for unit tests. It is also the replay engine: replaying a
cassette (M2) is a fake model fed from a file. So the design has to serve both a test author
writing responses by hand and a tape supplying them.

Experiment A fixed the constraints: the model reaches its executor only through
`executorConfiguration`, which must be `Hashable & Sendable`, and the session checks
`capabilities` before calling the executor.

## What the spike found (macOS 27.2, 2026-11-15)

A one-off script, not kept in the repo. Each line is a design input, and each is now pinned by
a test in `FakeModelTests`.

| Question | Answer |
|---|---|
| Does an error thrown by the executor reach the caller unchanged? | **Yes.** A custom error type arrives as itself. The fake can throw its own, well-worded error, and can simulate any `LanguageModelError` by throwing it. |
| How does a fake produce structured output? | **As JSON text** through `.appendText`, in one chunk or several. The model must declare `.guidedGeneration`. `respond(to:generating:)` then decodes it. JSON that doesn't fit the type throws `GenerationError`. |
| How many executors are created? | **One per session** (2 sessions, 3 calls: 2 inits). State that must outlive a session can't live in the executor. |
| Can state be shared through the configuration? | **Yes.** A reference type that is `Hashable` by identity passes through `Configuration` and is the same object in every executor. |
| Do stream snapshots match the chunks sent? | **No.** Three chunks gave four snapshots, and the first already held two chunks. A fake can't promise an exact snapshot sequence. |

## The central problem

A closure `(request) -> response` and a queue that advances are not `Hashable` values, and one
executor per session means the queue position can't sit in the executor. Both need shared,
mutable, thread-safe state reachable from the configuration.

## Options

1. **Value-only script.** The configuration carries an array of responses; no closures, no
   call recording. ❌ The queue can't advance across sessions and tests can't assert what was sent.
2. **Global registry keyed by ID.** The configuration carries a UUID; a global actor maps it
   to state. ❌ Leaks state between tests and needs cleanup.
3. **Reference box in the configuration.** `FakeModel` owns a `final class` state object
   (a `Mutex` inside, `Hashable` by identity); the configuration carries it. ✅ No globals.

## Decision

Option 3, with these choices:

| Question | Choice |
|---|---|
| Variadic or array? | **Both.** `FakeModel("a", "b")` reads well in tests; `FakeModel(responses)` is what a cassette will pass. |
| What happens when the responses run out? | **It fails**, always, with `FakeModelError.noResponseLeft(call:scripted:)`. A single response answers a single call. To answer any number of calls, use the closure form. |
| `calls` synchronous or `await`? | **Synchronous.** The lock is inside. |
| Name | **`FakeModel`**, as in the roadmap. |

```swift
let model = FakeModel("first", .json(#"{"name": "Pine Trail"}"#), .failure(Offline()))
let model = FakeModel { request in .text("saw \(request.transcript.count) entries") }

.text("late").delayed(by: .milliseconds(200))
.chunks(["Boil ", "water."])

#expect(model.calls.count == 2)
#expect(model.calls[0].prompt == "hi")
```

- **The failure is Assay's own error**, not Apple's empty-response error, whose type already
  changed once between 27.0.1 and 27.2.
- **Capabilities** are derived from the script: `.guidedGeneration` only if a JSON response is
  scripted. Declaring more than the fake can do would hide `unsupportedCapability` bugs. The
  closure form is text-only unless told otherwise.
- **Call recording** stores the prompt text, the request's transcript and options, and whether
  structured output was asked for. A call that fails is recorded too.

## Not in v0.1

- Tool calls and reasoning events.
- Exact control of stream snapshots (the framework coalesces chunks).
- Convenience constructors for `LanguageModelError` cases; `.failure(_:)` takes any error.
- Availability simulation: it isn't on the `LanguageModel` protocol, so it's a separate type
  and a separate decision ([0004](0004-availability-simulation.md)).

## Consequences

- ➕ Replay in M2 becomes "build a `FakeModel` from a tape", with no new executor.
- ➕ Failure messages are Assay's own, so they survive Apple changing its error types.
- ➖ A reference type inside a value type: copies of a `FakeModel` share one queue and one call
  log. That is the point, and it is documented on the type.

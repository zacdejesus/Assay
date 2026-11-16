# FoundationModels (OS 27): what M0 found

> 2026-11-07. Evidence: `Tests/AssayTests/ExperimentATests.swift`, `ExperimentBTests.swift`, and
> the SDK's `FoundationModels.swiftinterface` (iPhoneSimulator27.1.sdk). Experiment A's findings
> are pinned as characterization tests (`swift test`); Experiment B's live test is opt-in
> (`ASSAY_LIVE=1 swift test --filter ExperimentB`).

## The executor lifecycle

```
LanguageModelSession(model:)
  → model.executorConfiguration          (the only data the executor gets from the model)
  → Executor.init(configuration:) throws
  → prewarm(model:transcript:)           (optional warm-up)
  → respond(to: request, model:, streamingInto: channel) async throws
      the executor sends events; returning ends the response
  → session builds Response + appends Transcript entries
```

  - `LanguageModel` has exactly two requirements besides `Executor`: `capabilities` an
  `executorConfiguration`. **No availability on the protocol**: `availability` exists only on
  `SystemLanguageModel` and `PrivateCloudComputeLanguageModel`.
- `Self == Executor.Model`: model and executor name each other.
- `Configuration` must be `Hashable & Sendable`. Hypothesis (unverified): the framework caches
  executors by configuration.
- `respond` is `nonisolated(nonsending)`: it runs on the caller's actor.

## Experiment A: a fake model (✅ yes)

| Question | Answer |
|---|---|
| Can a custom `LanguageModel` back a real session in a unit test? | **Yes.** `fakeModelAnswersHello` passes in ~1 ms. |
| Executor sends nothing? | Throws. On macOS 27.0.1: `GeneratedContent.ParsingError`, "Session ended without producing a response." Since macOS 27.2: `LanguageModelError.unsupportedTranscriptContent`, "The model produced an empty response." |
| What's in the request? | `request.transcript` (instructions, prompts, earlier responses), `schema`, `generationOptions`, `enabledToolDefinitions`, `contextOptions`, `metadata`, `id`. All public. |
| Does the transcript accumulate? | **Yes.** The second call's request holds `Prompt first, Response hello, Prompt second`. |
| Are capabilities enforced? | **Yes.** A `@Generable` request to a model without `.guidedGeneration` throws `LanguageModelError.unsupportedCapability` **before** `respond` is called. |

How text goes out: `await channel.send(.response(action: .appendText("hello", tokenCount: 1)))`.

## Experiment B: wrapping the real model

| Question | Answer |
|---|---|
| Can an executor wrap `SystemLanguageModel`'s? | **Yes.** `SystemLanguageModel.Executor` is public, its `init(configuration:)` is public and non-throwing, and the configuration comes from `SystemLanguageModel.default.executorConfiguration`. `wrapperForwardsRealModel` got "pong" from the live model. |
| Can it put its own channel in between? | **Yes.** `LanguageModelExecutorGenerationChannel()` is public; events can be read from it and re-sent. **But it's racy by design:** the channel has no public `finish()`, so the reader can't know the last event arrived; cancelling it when the inner `respond` returns can drop buffered events (and leaks the reader if `respond` throws). The probe was removed after M0. |
| Can it read what the model said, through public API? | **No.** `Event`, `Response.Action` and the other actions are opaque: static constructors only, no accessors. `String(reflecting:)` shows the internals (`kind`, text, usage, metadata), but that's private layout, not API. |
| Can it read it at the session level? | **Yes, fully public.** `session.transcript` holds `.response` entries with `segments`, `assetIDs` and `metadata`. |

**Conclusion:** recording happens at the **session/transcript** level; replay happens at the
**executor** level (read the request, send events). Recording and replay use different APIs, so
the cassette key must be computed the same way from both sides.

## Model version identifier (open question for M4: ✅ answered)

`Transcript.Response` exposes, publicly:
- `assetIDs`, e.g. `com.apple.fm.language.instruct_3b.fm_api_generic_3b?variant=generic_sparse_16.1.0.13.103120,0`
  (plus the draft model and tokenizer assets);
- `metadata["systemVersion"]`, e.g. `Version 27.0.1 (Build 26A434)`.

The model assets carry their own versions (16.1.0… vs 16.0.…), separate from the OS build. That
confirms the prior-art worry: the model can change without an OS update, so provenance must store
`assetIDs`, not just the OS version.

## Surprises

- The real model also streams `updateUsage` and `updateMetadata` events, not only text.
- Errors come from two types: `LanguageModelError` (capabilities, context, guardrails, rate
  limits) and `GeneratedContent.ParsingError` (no or unparseable output). A fake must be able to
  simulate both.

## Experiment C: is the output repeatable? (2026-11-15, macOS 27.2)

Evidence: `Tests/AssayTests/ExperimentCTests.swift` (`scripts/test.sh greedy`). Each request was
sent 20 times, each time in a new session, with `maximumResponseTokens: 120`.

| Sampling | Short prompt | Open prompt | Structured (`@Generable`) |
|---|---|---|---|
| Default (`samplingMode: nil`) | not run | 20 distinct answers of 20 | not run |
| `.greedy` | 1 of 20 | 1 of 20 | 1 of 20 |
| `.random(top: 50, seed: 42)` | 1 of 20 | 1 of 20 | 1 of 20 |

- **The control works.** Default sampling gave 20 different answers on the open prompt, so the
  test can see variation, and "1 of 20" means something.
- **Greedy is repeatable**, also across processes (six runs in two separate processes gave the
  same SHA-256; checked with a one-off script, not pinned in a test).
- **A fixed seed is repeatable too**, and seeds 42 and 43 give different answers, so the seed is
  really used. A tape recorded with random sampling must store the seed and `top`.
- **Limits of this result:** one Mac, one model version, three prompts. Not checked: across
  devices, across model versions (by definition), long outputs, tool calls.

Two things have to be normalised before comparing anything:

- **`assetIDs` has no stable order.** The same three assets (tokenizer, model, draft model) come
  back in a different order from one response to the next. Sort them.
- **`GeneratedContent.jsonString` has no stable key order.** The same structured answer comes
  back as `{"highlights": …, "lengthInKilometers": …, "name": …}` or with the keys in another
  order. Re-serialize with sorted keys (or compare the decoded value).

Both matter for M2: a cassette key, a tape's provenance and a drift comparison must all use the
normalised form, or two recordings of the same answer from the same model will look different.

## What changed with macOS 27.2

Found on 2026-11-15, after this Mac went from 27.0.1 (26A434) to 27.2 (26B123):

- The model assets changed: the main model went from `…generic_sparse_16.1.0.13.103120` to
  `…generic_sparse_16.1000.0.13.103404`. The system and the model changed together here, so
  this is not evidence that the model updates without an OS update.
- An executor that sends nothing now makes the session throw
  `LanguageModelError.unsupportedTranscriptContent` instead of `GeneratedContent.ParsingError`.
  The characterization test in Experiment A caught it. A fake model's "no response left"
  failure (M1) can't rely on either error type staying the same.

## Streaming and usage (2026-11-16, macOS 27.2)

Found while building the example app (`Examples/TokenSpeed`). One run, 120-token limit:

- `ResponseStream.Snapshot.usage` is filled in while the response streams, so tokens per second
  can be measured live, without waiting for the final `Response`.
- The on-device model's snapshots arrived about every 10 output tokens (10, 20, 30, …), roughly
  every 0.25 to 0.3 s. So "time to first token" measured from snapshots is really the time to
  the first batch.
- The first request in a process took about 5.5 s to its first snapshot; a second request in
  the same process, about 1 s. A speed measurement has to keep that wait separate from the
  generation speed, which was around 35 to 38 tokens per second on this Mac.

## Experiment D: recording from inside an executor (2026-11-16, macOS 27.2)

The question M0 left open: recording needs the session level (public), replay needs the
executor level, so how does one model do both? Answer: the executor runs the request again in
a session of its own over the real model.

- A nested `LanguageModelSession` inside `respond(to:model:streamingInto:)` works.
- With greedy sampling the nested answer was identical to asking the model directly: plain
  text, instructions plus two turns, and structured output (compared as canonical JSON).
- The nested session is built with `LanguageModelSession(model:transcript:)` from every entry
  but the last prompt. `request.generationOptions` equals the last prompt's own `options`.
- For a `@Generable` request, `request.contextOptions.includeSchemaInPrompt` arrives as `true`.
- `Transcript` is `Codable` and round-trips, but each entry carries a generated ID.
- An encoded `GenerationSchema` doesn't keep a stable key order. Third case of the same thing,
  after `assetIDs` and `jsonString`: anything compared or hashed has to be made canonical first.

Details and the design that came out of it: [decisions/0005-cassette.md](../decisions/0005-cassette.md).

## Evaluations from the command line (2026-11-16, macOS 27.2, Xcode 27.1)

- `Evaluations.framework` ships next to `Testing.framework` (in the platform's
  `Developer/Library/Frameworks`), for macOS and for the iOS simulator. A SwiftPM test target
  imports it without extra settings, and `Evaluation.run()` works under `swift test`.
- An `Evaluation` produces its subject in its own `subject(from:)`, and `ModelJudgeEvaluator`
  takes `judge: any LanguageModel`. So a cassette's model fits both without an adapter.
- The judge asks for structured output: a schema titled `Rating` with `<dimension>_value` (an
  enum of the scale's values as strings) and `<dimension>_rationale`.
- The judge's prompt is built from several parts and contains the answer being scored. A
  changed answer is therefore a different judge request.
- The `.evaluates(...)` test trait was not tried.

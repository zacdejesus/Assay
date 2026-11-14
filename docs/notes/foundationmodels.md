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
| Executor sends nothing? | Throws `GeneratedContent.ParsingError`: "Session ended without producing a response." |
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

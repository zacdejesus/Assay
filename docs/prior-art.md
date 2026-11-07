# Prior Art & Landscape

> **Who else is doing what Assay wants to do?** This is a dated snapshot. When I re-check,
> I **add** a new entry to the [check-in log](#check-in-log) instead of rewriting history,
> so I can watch the gap grow or shrink over time.

**Snapshot:** 2026-09-21 · **Method:** web search + reading Apple's WWDC26 session pages,
GitHub READMEs and blog posts. **Confidence:** ✅ read from a primary source (Apple / the
repo itself) · 🟡 second-hand (blog / summary) · ❓ couldn't verify.

---

## TL;DR: the landscape changed at WWDC26 (June 2026)

The README was written for the iOS 26 world. Two Apple announcements move the ground
under Assay:

1. **FoundationModels now has a public `LanguageModel` protocol** (OS 27). ✅
   `LanguageModelSession(model:)` accepts any conforming model, backed by a
   `LanguageModelExecutor` you implement. **That is the "seam" Assay's M1 was going to
   invent.** Apple invented it first. A mock or a cassette can just *be* a `LanguageModel`.
2. **Apple shipped an official `Evaluations` framework** (Xcode 27, all Apple platforms). ✅
   Datasets (`ModelSample`), evaluators (`Evaluator`, `Metric`), LLM judges
   (`ModelJudgeEvaluator`, `ScoreDimension`), aggregates (`MetricsAggregator`), a Swift
   Testing trait (`.evaluates(...)`), Xcode reports, and run-vs-run comparison.
   **That covers most of Assay's M3–M5** (matchers, judge, eval suites).

**What's still uncovered (Assay's real niche, as of today):**

- **Record/replay of model interactions**, especially on-device, where HTTP-level tools
  can't help because there's no HTTP.
- **Running AI-feature tests offline in CI**, where the on-device model can't run. Apple's
  Evaluations needs a live model.
- **Availability simulation** for the fallback UI (no official way found).
- **A ready-made scripted/fake model for unit tests.** Now *possible* via Apple's protocol,
  but nobody packages it (that I found).
- **Tracking behaviour drift across OS/model versions.** Partly possible with Xcode's
  compare view and `xceval`, but nothing is built for "the OS update changed my model".

➡️ Strategic read: **don't compete with Apple's Evaluations. Complement it.** Assay becomes
the *deterministic, offline* layer (mocks, availability, cassettes, CI, drift) that plugs
*into* Apple's `LanguageModel` protocol and can feed Apple's `Evaluations`.
See [pending.md](pending.md) for the decision this forces.

---

## The players

### Apple: FoundationModels `LanguageModel` protocol (OS 27) ✅
- `protocol LanguageModel: Sendable` with `capabilities` and `executorConfiguration`.
- `protocol LanguageModelExecutor: Sendable` with `init(configuration:)`,
  `prewarm(model:transcript:)`, and
  `respond(to: LanguageModelExecutorGenerationRequest, model:, streamingInto: LanguageModelExecutorGenerationChannel) async throws`.
- Conformers: `SystemLanguageModel`, `PrivateCloudComputeLanguageModel`, open-source
  `CoreAILanguageModel` / `MLXLanguageModel`, plus Anthropic (`ClaudeForFoundationModels`)
  and Google (Gemini) packages 🟡.
- Shared error type `LanguageModelError` (`contextSizeExceeded`, `rateLimited`, `refusal`,
  `guardrailViolation`, `timeout`, …) ✅.
- Responses now carry `response.usage` (input/cached/output/reasoning token counts) ✅.
- **Testing:** the session doesn't mention mocks or fakes at all. Mocking is *implied*
  by the protocol, not provided.
- ❓ Does the protocol expose **availability**, or is that still only on `SystemLanguageModel`?
  This decides whether availability simulation "just works" or still needs a wrapper.
- Source: WWDC26 [339 "Bring an LLM provider to the Foundation Models framework"](https://developer.apple.com/videos/play/wwdc2026/339/),
  [241 "What's new in the Foundation Models framework"](https://developer.apple.com/videos/play/wwdc2026/241/).

### Apple: `Evaluations` framework (Xcode 27) ✅
- You conform to the `Evaluation` protocol: a subject, a dataset (`ModelSample`, loaders
  like `ArrayLoader`), evaluators, and `aggregateMetrics(using:)`.
- `Metric` + `Evaluator` for code-checkable criteria; `ModelJudgeEvaluator` + `ScoreDimension`
  for qualitative ones. Apple recommends a **judge at least as capable as the model under
  test** (e.g. Private Cloud Compute).
- Runs inside Swift Testing via `@Test(.evaluates(evaluation, info:))`; results in
  `EvaluationContext.current.result`, asserted with `#expect(... >= 0.8)`.
- Xcode 27 report with per-sample detail and a **compare two runs** view (baseline vs.
  experiment).
- Also 🟡: `SampleGenerator` (synthetic datasets), `ToolCallEvaluator` +
  `TrajectoryExpectation` (agent tool-call checks), `ArgumentMatcher`.
- **Not mentioned anywhere I read:** mocking, record/replay, CI/`xcodebuild` usage,
  on-device model changes across OS updates, pass@k / pass^k.
- Sources: [298 "Meet the Evaluations framework"](https://developer.apple.com/videos/play/wwdc2026/298/),
  [335 "Improve your prompts by hill-climbing with Evaluations"](https://developer.apple.com/videos/play/wwdc2026/335/),
  [299 "Create robust evaluations for agentic apps"](https://developer.apple.com/videos/play/wwdc2026/299/),
  [docs](https://developer.apple.com/documentation/evaluations),
  [Designing effective model-as-judge evaluators](https://developer.apple.com/documentation/Evaluations/designing-effective-model-judges).

### Apple: other WWDC26 pieces
- [`apple/foundation-models-utilities`](https://github.com/apple/foundation-models-utilities)
  (Apache-2.0): Skills API, history modifiers, `ChatCompletionsLanguageModel`. "Emerging and
  experimental." No testing tools 🟡.
- `fm` CLI on macOS 27 (`respond`, `chat`, `available`, `serve`, …) and a Python SDK
  (`apple-fm-sdk`) 🟡. `fm available` could help check a machine's status.
- Apple said the FoundationModels framework itself would be **open-sourced "later this
  summer"** (incl. Linux) 🟡. ❓ As of 2026-09-21 I **could not confirm** it has shipped.
  If it has, running the stack on Linux CI becomes a question worth asking.

### Hugging Face: AnyLanguageModel 🟡
- [github.com/huggingface/AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel):
  ~939★, v0.13.0. API-compatible drop-in for FoundationModels with many providers.
- README now says: "On OS 27, Foundation Models accepts any type that conforms to its
  `LanguageModel` protocol." Still useful for **OS 26** support.
- No mock/testing models; its own tests hit real backends.

### mattt/Replay: HTTP record/replay for Swift Testing ✅
- [github.com/mattt/Replay](https://github.com/mattt/Replay): ~295★, MIT, Swift 6.1+.
- HAR fixtures, `@Test(.replay("name"))` trait, record modes (`none` / `once` /
  `rewrite`), playback modes (`strict` / `passthrough` / `live`), composable matchers,
  redaction (`.headers(removing: ["Authorization"])`).
- **This is the best design reference for Assay's Cassette** (same author as
  AnyLanguageModel). But it works at the **HTTP** level: great for cloud LLMs,
  **useless for the on-device model** (no HTTP). No LLM awareness.

### swift-vcr 🟡
- [Nosaakhtare1/swift-vcr](https://github.com/Nosaakhtare1/swift-vcr): Ruby-VCR port for
  `URLSession`. HTTP only, same limits as Replay.

### xceval: Evaluations-Framework-CLI (unofficial) ✅
- [rudrankriyam/Evaluations-Framework-CLI](https://github.com/rudrankriyam/Evaluations-Framework-CLI):
  ~32★, MIT. Runs Apple Evaluations, **compares baseline vs. candidate** (per sample:
  regressed / fixed / modified / added / removed), **absolute & delta gates**, CI-friendly
  JSON output.
- ⚠️ **Closest thing to my "model drift" idea and to the M5 CI gate.** Study it before
  building either. Still needs a *live* model to produce the runs.

### Foundation Lab (rudrankriyam) 🟡
- [Foundation-Models-Framework-Lab](https://github.com/rudrankriyam/Foundation-Models-Framework-Lab):
  ~1.2k★. An app/workbench: run history, transcripts, token usage, experiment comparison.
  Not a test library. No mocks, replay or availability simulation.

### swift-evals (ltloop) ❓
- Listed on [Swift Package Index](https://swiftpackageindex.com/ltloop/swift-evals) as
  "a Swift library for evaluating Foundation Model LLM". Very small (few commits, 1
  release). Page returned 403; not inspected.

### Articles / patterns (no library)
- Wesley Matlock, ["Testing Foundation Models"](https://www.wesleymatlock.com/testing-on-device-ai-swift-testing/)
  🟡: "three rings": (1) assert shape, not words; (2) mock the model behind a protocol
  and test the logic around it; (3) evals as rates. Gates live tests behind
  `RUN_LIVE_AI_TESTS=1`. **Good framing for Assay's README.**
- The common community advice for availability is "wrap `SystemLanguageModel.default.availability`
  behind your own protocol" ([dev.to example](https://dev.to/arshtechpro/how-to-fall-back-gracefully-when-apple-intelligence-isnt-available-48j)).
  Everyone re-writes it by hand, which is a sign a library could help.

### Outside Swift (reference, not re-verified today)
- **promptfoo**, **DeepEval** (Python/JS eval frameworks, LLM judges, CI).
- **VCR / vcrpy**, and LLM-specific cassettes (`vcr-langchain`, `langchain-replay`,
  `codesweep-ai/vcr`, `faisalkhan91/Cassette`): record/replay is an established idea
  elsewhere; it's the *Swift + on-device* combination that's missing.

---

## Coverage matrix: the metric

Each Assay capability, scored against the best existing option **as of the snapshot date**.
`0` = nobody does it · `1` = partial / DIY-possible / unofficial · `2` = solidly covered.

| # | Capability                                      | Best existing option                              | Score |
|---|-------------------------------------------------|---------------------------------------------------|:-----:|
| 1 | Swap the model behind a seam                     | Apple `LanguageModel` protocol (OS 27)            | 2 |
| 2 | Scripted fake model for unit tests               | DIY via Apple's protocol; not packaged            | 1 |
| 3 | Availability simulation (fallback UI)            | DIY wrapper protocol (blog pattern)               | 1 |
| 4 | Record/replay: cloud LLM (HTTP)                  | mattt/Replay, swift-vcr (not LLM-aware)           | 1 |
| 5 | Record/replay: **on-device** model               | nothing found                                     | 0 |
| 6 | Offline, free AI tests in CI                     | nothing found (Evaluations needs a live model)    | 0 |
| 7 | Deterministic output checks (matchers)           | Evaluations `Evaluator`/`Metric`, `#expect`       | 2 |
| 8 | LLM-as-judge                                     | Evaluations `ModelJudgeEvaluator`                 | 2 |
| 9 | Judge calibration vs. my human labels            | Apple docs give guidance; no tooling seen ❓       | 1 |
|10 | Eval suites + pass-rate aggregates               | Apple Evaluations                                 | 2 |
|11 | pass@k / pass^k                                  | not seen in Apple's APIs ❓                        | 0 |
|12 | Compare runs / regression CI gate                | Xcode 27 compare view; xceval gates               | 1 |
|13 | Tool-call trajectory assertions                  | Evaluations `ToolCallEvaluator` 🟡                 | 2 |
|14 | Drift across OS / model versions                 | xceval compare *could* do it; nothing dedicated   | 1 |
|15 | Latency & token/cost accounting                  | `response.usage`, Xcode 27 Instruments            | 2 |

**Gap score = sum of (2 − score) = 11 / 30.** Higher = more room for Assay.
**Open gaps (score 0):** #5 on-device record/replay, #6 offline CI, #11 pass^k.

How to re-score: re-check each row's "best existing option", update the score, recompute,
and append a row to the log below. A dropping gap score means the niche is closing: time
to re-think scope.

---

## Check-in log

| Date       | Gap score | What changed                                                                 |
|------------|:---------:|------------------------------------------------------------------------------|
| 2026-09-21 | 11 / 30   | First snapshot. WWDC26 `LanguageModel` protocol + Evaluations framework cover the seam, matchers, judge and eval suites. Remaining niche: on-device record/replay, offline CI, availability sim, packaged fakes, drift. |

## To re-check next time

- [ ] Has the FoundationModels framework actually been open-sourced? Linux?
- [ ] Does `LanguageModel` (or a new API) expose availability?
- [ ] Does Apple add any fake/mock model or record/replay to FoundationModels or Evaluations?
- [ ] Do Apple Evaluations run from `xcodebuild test` / CI? Can GitHub-hosted macOS runners
      run the on-device model or PCC? (Very likely not, but verify.)
- [ ] Inspect `swift-evals` properly.
- [ ] Search Swift Package Index for new "mock language model" / "cassette" packages.
- [ ] Does AnyLanguageModel (or mattt) ship an LLM-aware Replay? It's the obvious next step for them.

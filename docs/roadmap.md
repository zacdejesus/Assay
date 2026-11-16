# Assay Roadmap

> **v2, 2026-09-22.** Rewritten after WWDC26 changed the landscape
> ([prior-art.md](prior-art.md)) and the positioning decision
> ([decisions/0001-positioning.md](decisions/0001-positioning.md)).
>
> This is a learning project (see [CLAUDE.md](../CLAUDE.md)). Each milestone teaches what
> the next one needs. Understanding over speed.

---

## The one-sentence version

**Assay is the memory and regression detector for Apple's language models.** It records
what the model answered, replays it offline, and tells you what changed when Apple ships
a new model.

- **Cassettes are the mechanism.** Recorded, versioned, committed answers.
- **Drift is the product.** "iOS 27.1's model broke 3 of your 40 cases; here are the diffs."
- **Apple's frameworks are allies.** Assay builds *on* the `LanguageModel` protocol and
  *feeds* Apple's `Evaluations`. It never re-implements them.

---

## The filter every feature must pass

Before building anything, ask two questions:

1. **Could Apple ship this as a checkbox in the next Xcode?**
2. **Would Apple *want* to?**

| Both "yes"          | Build it small, as a utility, and expect to delete it someday. |
|---------------------|----------------------------------------------------------------|
| Either "no"         | That's the moat. This is where the effort goes.                |

Things that fail the second question (Apple doesn't want to): exposing regressions in
its own model, keeping the history of models it replaced, neutral comparisons against
competitors, workflows outside Xcode (plain `swift test`, GitHub Actions, Linux).

---

## What changed from v1 (and why)

| v1 idea                         | v2 decision                          | Why |
|---------------------------------|--------------------------------------|-----|
| Own seam protocol               | ❌ Use Apple's `LanguageModel`        | Apple shipped it at WWDC26. |
| `MockModel` as headline         | ⬇️ Small utility (`FakeModel`)        | Trivial for Apple to copy; still needed as the replay engine. |
| Availability simulation         | ⬇️ Small utility                      | StoreKit Testing shows Apple does ship this kind of thing. |
| Cassette                        | ⬆️ Core mechanism                     | Apple has never shipped a recorder in 15 years of XCTest. |
| Matchers, `#judge`, eval suites | ❌ Delegated to Apple's `Evaluations` | Already shipped. Competing with Apple here is a losing game. |
| Judge calibration               | ❌ Dropped                            | Apple publishes guidance; not Assay's fight. |
| Drift (was an M6+ idea)         | ⬆️ **The headline**                   | Hardest to copy: against Apple's incentives. |

---

## Milestone map

```
M0  Spike & foundations        ──►        can I plug into Apple's protocol at all?  (gate)
M1  FakeModel + availability   ──► v0.1   the replay engine; small utilities
M2  Cassette                   ──► v0.2   record once, replay forever, with provenance
M3  Evaluations bridge         ──► v0.3   Apple's evals, offline, in CI
M4  Drift report               ──► v0.4   ★ what changed when Apple changed the model
─────────────────────────────── core ends here ───────────────────────────────
M5  Neutral comparison         ──► v0.5   on-device vs PCC vs Claude vs Gemini
M6+ Beyond                                public drift ledger, streaming, tools, Linux
```

**Core = M0–M4.** If I only ever finish those, Assay is complete and useful.

Each milestone lists: **Why · Learn · Build · Decide · Done when · Traps · Apple risk.**
Sizes are effort (S/M/L), not dates.

---

## M0: Spike & foundations  · size **M** · 🚦 gate

**Why:** The whole plan assumes I can (a) implement a fake `LanguageModel` that runs in
plain unit tests, and (b) *wrap* a real model to record it. If either is false, the
architecture changes. Find out before writing anything else.

**Learn**
- SwiftPM by hand: targets, products, platforms, test targets.
- Swift Testing: `@Test`, `@Suite`, `#expect`, `#require`, `withKnownIssue`, traits.
- FoundationModels OS 27: `LanguageModel`, `LanguageModelExecutor`,
  `LanguageModelExecutorGenerationRequest`, `LanguageModelExecutorGenerationChannel`,
  `Transcript`, `GenerationOptions`, `LanguageModelError`, `response.usage`.
- Swift 6 strict concurrency basics (`Sendable`, actors).

**Build**
- [ ] `Package.swift` + one green `swift test`.
- [ ] Example app ("recipe steps") using `LanguageModelSession` with a fallback screen.
- [ ] **Experiment A: fake.** Smallest `LanguageModel` + executor that always answers
      `"hello"`, used via `LanguageModelSession(model:)` in a unit test.
- [ ] **Experiment B: wrap.** Can my executor *forward* to another model's executor
      (e.g. `SystemLanguageModel`)? Is that executor even public/constructible?
- [ ] Notes in `docs/notes/foundationmodels.md` and `docs/notes/environment.md`.

**Decide**
- **Minimum OS: 27+ only?** Recommended: yes. Apple's protocol only exists there, and
  supporting OS 26 (via AnyLanguageModel or an own seam) doubles the work for a shrinking
  audience. Write the decision down.
- **Where does recording happen?** Depends on Experiment B:
  - B works → record at the **executor** level (a decorator model). Cleanest: transparent
    to the app.
  - B fails → record at the **session/response** level (the app calls through an Assay
    helper, or Assay reads `session.transcript`). Less transparent, still workable.

**Done when:** both experiments have a written yes/no answer with evidence, and I can
explain the executor lifecycle (configuration → executor → respond → channel) from memory.

**Traps**
- Assuming Experiment B works because it "should". It's the single biggest unknown.
- The on-device model needs an eligible device/OS. Know what runs where before M2.

**Apple risk:** n/a (learning).

---

## M1: FakeModel + availability  · **v0.1** · size **S–M**

**Why:** Two reasons. (1) Unit tests of app logic need a scripted model. (2) More
important for Assay: **replaying a cassette *is* a fake model fed from a file.** Building
the fake first builds the replay engine.

**Learn**
- Conforming to a framework protocol you don't control; associated types; `Sendable`.
- Concurrency-safe call recording (tests run in parallel by default).
- API design: `public` surface, naming, defaults. DocC.

**Build**
- [x] `FakeModel`: a `LanguageModel` with scripted responses: fixed, queue, or closure
      `(request) -> response`.
- [x] Simulated errors (`LanguageModelError` cases: `contextSizeExceeded`,
      `guardrailViolation`, `rateLimited`, …) and simulated latency.
- [x] Call recording: assert which prompts were sent, how many times.
- [x] **Availability simulation** (every unavailable reason + transitions such as
      `modelNotReady` → `available`). M0 found it only on `SystemLanguageModel`, so it is a separate
      type, `AvailabilityScript` ([decision 0004](decisions/0004-availability-simulation.md)).
- [x] Example app: test that the fallback UI appears when the model is unavailable
      ([Examples/TokenSpeed](../Examples/TokenSpeed)).

**Decide**
- Structured output (`@Generable`) in v0.1? Suggest: text first, but prove the design can
  grow into it without breaking changes.

**Done when:** the example app's fallback-UI test and an error-path test run in < 1 s,
offline, and a misconfigured fake fails with a clear message.

**Traps:** over-building. This is a utility, not the product. Keep it small.

**Apple risk: 🔴 high.** Apple could ship `FakeLanguageModel` / availability overrides next
year. That's fine: if they do, Assay's replay engine switches to theirs.

---

## M2: Cassette  · **v0.2** · size **L** · core mechanism

**Why:** Record the real model once, commit the tape, replay it deterministically anywhere,
and **preserve what an Apple model said after Apple has replaced it.** That last part is
what makes M4 possible.

**Learn**
- `Codable` in depth; stable, diff-friendly output (`.sortedKeys`, `.prettyPrinted`);
  versioned formats.
- **Stable hashing:** `Hasher` is randomly seeded per process, so it can't name files.
  Use a real digest (SHA-256 via CryptoKit or swift-crypto).
- Files next to tests via `#filePath` (the swift-snapshot-testing trick); atomic writes.
- Custom Swift Testing traits (`@Test(.cassette("recipe"))`) and test scoping.
- Prior art to study: **mattt/Replay** (modes, matchers, redaction, trait API), VCR/vcrpy.

**Build**
- [x] Tape format v1 (JSON): `version`, interactions (request key → response), and
      **provenance**: OS version + build, model identifier (if exposed), device class,
      generation options, recorded-at date, Assay version. *Provenance is non-negotiable:
      M4 depends on it.*
- [x] Modes: `.replay` (never live; missing tape = failure), `.record` (always live),
      `.auto` (replay if present, else record). **In CI: never record, ever.**
- [x] Request matching: prompt + instructions + options + schema, with a hook for custom
      normalisation (timestamps, IDs).
- [x] Mismatch = loud failure showing the closest recorded request.
- [x] Redaction hook (unused until cloud models, but designed now).
- [x] Tapes in `__Cassettes__/` next to the test (already un-ignored in `.gitignore`).
- [x] Documented "re-record" workflow.

**Decide**
- One file per test or per interaction? Match by key or replay in order?
- Record with **greedy sampling** by default so a tape reflects *the model*, not sampling
  luck? (Verify Apple documents greedy as deterministic for a given model.)
- How to store structured output and (later) tool calls: `GeneratedContent` JSON?
  `Transcript` entries? Check what round-trips losslessly.

**Done when:** I record a tape from the real on-device model, then on a machine *without*
Apple Intelligence the same test passes bit-for-bit, and a missing tape in CI fails with
instructions on how to record it.

**Traps**
- Silent recording in CI. Two parallel tests writing one tape. Secrets in tapes.
- Pretending tapes are eternal. They're a snapshot of *one* model; that's a feature (M4),
  not a bug, but it must be visible.

**Apple risk: 🟡 medium.** Possible but out of character: Apple has never shipped a
recorder (not for HTTP, not for anything).

---

## M3: Evaluations bridge  · **v0.3** · size **M**

**Why:** Apple's `Evaluations` needs a live model, so it can't run in CI or on machines
without Apple Intelligence. Cassettes can feed it. Assay makes Apple's framework *more*
useful instead of competing with it.

**Learn**
- Apple's `Evaluations`: `Evaluation` protocol, `ModelSample`, `Evaluator`, `Metric`,
  `ModelJudgeEvaluator`, `MetricsAggregator`, `.evaluates(...)` trait.
- The difference between a test (pass/fail) and an eval (a rate over a dataset).
- Composition with someone else's framework: adapters, not wrappers of everything.

**Build**
- [x] A cassette-backed model used as the subject of an Apple `Evaluation`.
- [x] **Judge calls recorded too**, so judged evals replay offline.
- [ ] Example: the example app's evaluation running in `swift test` / `xcodebuild test`
      with no live model.
- [x] A guide: "run Apple Evaluations in GitHub Actions with Assay".

**Decide**
- Does Evaluations run from the command line at all? **Yes** (2026-11-16): `import
  Evaluations` and `Evaluation.run()` work under `swift test`.
- Replayed evals are deterministic: fine for regression gating, meaningless for
  measuring variance. Say so in the docs.

**Done when:** an Apple `Evaluation` (including a model judge) runs green in CI from tapes,
and a deliberate regression in the recorded data makes it fail.

**Traps:** re-implementing parts of Evaluations "because it's easier". If Apple has it, use it.

**Apple risk: 🟢 low.** Apple's evaluation story is Xcode + live models.

---

## M4: Drift report  · **v0.4** · size **L** · ★ the headline

**Why:** Apple ships a new on-device model with OS updates, without asking. Your feature
can silently get worse. Only one model version exists on a device at a time, so the old
behaviour survives **only if someone recorded it.** Assay did (M2). Apple will never build
a tool whose job is exposing its own model's regressions. That's the moat.

**Learn**
- Designing a comparison: what's a meaningful "change" in non-deterministic output?
- Basic statistics: sample size, noise vs. signal, why "85% → 82%" on 20 cases proves
  little. Show counts, not just percentages.
- Building a CLI: a SwiftPM command plugin or executable target; Markdown report output.
- Prior art: **xceval**'s baseline/candidate compare (regressed / fixed / modified).

**Build**
- [ ] **Tape generations:** tapes grouped by provenance (e.g. `iOS 27.0 (24A…)` vs
      `iOS 27.1`), so old recordings are *kept* when re-recording, not overwritten.
- [ ] `assay drift` command: re-run a suite live on the current model, compare against
      the previous generation.
- [ ] Per-case classification: **unchanged / changed-but-passing / flipped-to-fail /
      flipped-to-pass**, using Apple `Evaluations` metrics (M3) or `#expect`-style checks
      as the pass criterion.
- [ ] Latency and token-usage deltas (`response.usage`).
- [ ] Markdown report with diffs of flipped cases.
- [ ] CI gate: fail if flipped-to-fail > threshold.

**Decide**
- One sample per case, or k samples to separate model change from sampling noise?
  (Greedy recording from M2 may make one sample enough; verify.)
- How to identify a "model version" if Apple doesn't expose one: OS build is a proxy, but
  the model asset may update separately. (Open question from prior-art.)
- Keep all generations forever, or last N?

**Done when:** after an OS update I run one command and get "37 unchanged, 3 flipped to
fail, 1 flipped to pass", with diffs, and the CI gate fails on the 3.

**Traps**
- Calling every wording change a regression. Drift that still passes is information, not
  failure.
- Big percentages from tiny suites.

**Apple risk: 🟢 very low.** It goes against Apple's incentives.

---

## M5: Neutral comparison  · **v0.5** · size **M** · after core

**Why:** "Is my feature better with the on-device model, PCC, Claude or Gemini, and what
does each cost?" Apple won't make a neutral cost comparison against competitors.

**Build**
- [ ] Run the same suite against several `LanguageModel`s (on-device, PCC, Anthropic,
      Google packages), recorded as cassettes per provider.
- [ ] Report: pass rate, flips between providers, latency (p50/p95), tokens, **estimated
      cost** (a user-supplied price table; never hard-coded prices).
- [ ] Redaction active for cloud tapes (API keys, user data).

**Apple risk: 🟢 low.**

---

## M6+: Beyond · unordered

- **Public drift ledger:** a public record of how Apple's on-device model behaves across OS
  versions on a fixed prompt set ("Can I Use", for Apple Intelligence). ⚠️ Outward-facing:
  needs my explicit decision before any publishing.
- **Streaming** and **tool-call** recording in cassettes.
- **pass^k** reporting, if Apple's Evaluations still lacks it.
- **Linux CI**, if Apple really open-sources FoundationModels.
- **1.0**: API freeze, full DocC, only after real use.

---

## Explicitly *not* doing

- Own matchers, own judge, own eval-suite runner. → Apple `Evaluations`.
- Own provider abstraction. → Apple `LanguageModel`.
- Judge calibration tooling.
- A hosted dashboard. A prompt manager.
- OS 26 support (unless the M0 decision says otherwise).

---

## Every milestone

- [ ] DocC on every public symbol, with an example.
- [ ] Failure messages tested (a bad message is a bug).
- [ ] Example app uses the new feature.
- [ ] CHANGELOG under `[Unreleased]`.
- [ ] Non-obvious choices written down in `docs/decisions/`.
- [ ] Run the Apple-risk filter again; re-check [prior-art.md](prior-art.md) after each WWDC/beta.
- [ ] I tag `0.x.0` myself when "Done when" is met.

---

## Reading list

- WWDC26: 339 (LLM provider / `LanguageModel`), 241 (What's new in FoundationModels),
  298 & 335 (Evaluations), 299 (agentic evals).
- mattt/Replay source: the Cassette's closest design reference.
- xceval: baseline/candidate comparison, for M4.
- swift-snapshot-testing: `#filePath` storage and record modes.
- VCR / vcrpy docs: 15 years of record/replay lessons.
- Hamel Husain and Eugene Yan on evals (context for M3/M4).
- Swift API Design Guidelines.

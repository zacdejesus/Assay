# 0006: Drift report

- **Status:** Accepted (2026-11-23). Proposed 2026-11-16, drafted and implemented by Claude
  after Experiment E; the three "Decide" questions of roadmap M4 were answered with Claude's
  recommendations, confirmed after the macOS 27.2.1 run.
- **Context docs:** [roadmap M4](../roadmap.md), [0005: Cassette](0005-cassette.md)
- **Code:** `Sources/Assay/Drift.swift`, `Sources/AssayCLI/main.swift`, `Tests/AssayTests/DriftTests.swift`

## Context

Apple replaces the on-device model with OS updates. Only one version exists on a device, so
what the previous one answered survives only if it was recorded. Tapes (M2) are that record.
M4 compares a tape with what the current model answers.

## Experiment E (macOS 27.2, 2026-11-16)

Can a request stored in a tape be sent again and get the same answer from the same model?

| Question | Answer |
|---|---|
| A prompt built from parts, stored as one text with a line per part? | **Same answer** as the parts (2 prompts). Stored glued together without line breaks, the answer differed in 1 of 2: the parts are not just concatenated. |
| A schema decoded back from its canonical JSON? | **Same answer** as the `@Generable` type. |
| A transcript rebuilt from the stored instructions and earlier turns? | **Same answer** as the original session's second turn. |
| All 9 requests of the committed tapes, asked again? | **9 unchanged**, including the model judge's multi-part structured requests. |

So a tape is enough to repeat its requests. No test code has to run.

## Decision

`Drift.check(tape:)` asks the current model every request in a tape again and returns a
`DriftReport`. `Drift.compare(baseline:candidate:)` compares two tape files without a model.
An `assay` command wraps both.

| Question (roadmap) | Choice |
|---|---|
| One sample per case, or k? | **One**, with greedy sampling. Experiment C: greedy is repeatable (20/20), so a different answer means something changed, not sampling noise. A tape recorded with random sampling and no seed will show changes that aren't drift; the report can't tell. |
| What identifies a model version? | **The sorted `assetIDs`.** The OS build is shown but not compared: the same assets under a new build are not a new model. `report.modelChanged` says which case it is. |
| Keep all generations, or the last N? | **All.** They are small text files, and deleting one is `git rm`. |

**Classification.** With a pass criterion (`(request, answer) -> Bool`): unchanged, changed
(still passing), flipped to fail, flipped to pass, still failing. Without one: unchanged or
changed. Requests on one side only: added, removed.

**Generations.** When a tape is replaced by answers from a different model, the old file moves
to `__Cassettes__/generations/<name>/<system>-<build>-<digest>.json`. This happens both when a
test records again and with `assay drift --update`. The same model just replaces the tape.

**The report** is Markdown: what was compared, counts (not percentages), token and time totals,
and the before and after of every case that isn't unchanged, failures first.

**The gate.** In a test: `#expect(report.count(.flippedToFail) == 0)`. From the command line,
where there is no pass criterion: `--fail-on-change`.

## Revision: randomly sampled requests (2026-11-23)

Real features ship with random sampling, so their tapes do too, and a drift report over them
was all noise: with the same model, minutes apart, 12 of 12 randomly sampled requests in
`Examples/PickTwo` came back "changed" while 24 of 24 greedy ones were unchanged. The tape
stores the sampling mode, so the report can tell them apart.

- A request recorded with random sampling **and no seed** whose answer differs, and that still
  passes (or has no pass criterion), is `sampled` ("changed, randomly sampled"), not `changed`.
  A seed makes it comparable again (Experiment C: seeded sampling is repeatable), and no
  sampling mode means greedy.
- Flips stay flips. With a pass criterion, a randomly sampled answer that now fails is shown as
  flipped to fail: the outcome matters even when sampling may have caused it. Ask again before
  concluding.
- `sampled` cases are listed last and don't count for `--fail-on-change` (`changeCount`). The
  report says how many cases were randomly sampled.

To compare models, record with greedy sampling or a seed. A test can keep the app's options
for its own assertions and record a second, greedy tape for drift, as `Examples/PickTwo` does.

## Not in this version

- The command line has no pass criterion, so it can't say "flipped to fail"; that needs the
  library API, called from a test. Apple `Evaluations` metrics as the criterion: run the
  evaluation on each generation's tape and compare the results (not automated).
- A text diff inside an answer. The report shows before and after in full.
- Time to answer is recorded but noisy (first request of a process); it is reported as a
  total, with that warning, and never gates.
- A tape whose answers feed another tape's requests (a judge scoring recorded answers) is
  checked request by request. If the answers change, the judge's stored requests are stale
  and both tapes have to be recorded again from the tests.

## Consequences

- ➕ One command after an OS update: `scripts/test.sh drift`.
- ➕ Old answers are kept by default; nothing has to be remembered before recording again.
- ➖ Not yet run across a real model change. macOS 27.2.1 (2026-11-20) shipped the same model
  assets: 9 of 9 unchanged, and the report said "the same on both sides", as designed.
- ➖ "Unchanged" means byte-identical text. Any rewording is "changed", which is why changed
  is information and not a failure.

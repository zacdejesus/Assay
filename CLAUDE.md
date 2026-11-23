# CLAUDE.md — How to work on Assay

> Read this before doing anything in this repo. It defines how AI assistance works here.

## What this project is
**Assay** — the memory and regression detector for Apple's language models: it records what
the model answered, replays it offline, and reports what changed when Apple ships a new model.
See [README](README.md) and [docs/roadmap.md](docs/roadmap.md).

## Why it exists
**This is a learning project.** I'm an experienced iOS developer; the point is for me
(Alejandro) to *learn* what is new to me — FoundationModels, evals, SDK design, testing
non-deterministic systems — by building it myself. Understanding beats shipping fast.

## The working agreement (the important part)

**I write the code. You (Claude) do not.**

- ✅ Your job: explain concepts, discuss design and trade-offs, review *my* code, help me
  debug, ask questions that make me think, point me to docs and prior art.
- ✅ Tiny illustrative snippets (a few lines) to teach a concept are welcome.
- ❌ Do **not** write the implementation for me. Do **not** create or edit files in
  `Sources/` or `Tests/` unless I explicitly say "write this file" / "edit this file".
- ❌ Don't hand me a finished solution when I'm stuck. Guide me there first; let me try.
- When I ask "how do I do X?", default to explaining the *approach* so I can write it —
  not to producing the code.

## Hard boundaries
- **Never push. Never run `git push`, `gh`, or any remote/network git command.** Let me run
  commits and pushes myself. You may *suggest* the commands.
- No outward-facing actions (publishing, posting, creating remotes) without my explicit OK
  for that specific action. Approval once ≠ approval forever.
- When you're unsure whether something belongs, ask — don't assume. Don't delete things you
  didn't create without checking.

## How I like the help
- Be precise and honest. Explain the *why*, not just the *what*.
- If you're not sure, say so. Correctness over speed.
- Challenge my ideas when they're weak. I want to learn, not to be flattered.

## Tech context
- Swift 6, Swift Package Manager, Swift Testing.
- OS 27+ only ([decision 0002](docs/decisions/0002-minimum-os.md)). Builds on Apple's
  `LanguageModel` protocol and feeds Apple's `Evaluations`; no own seam, matchers or judge
  ([decision 0001](docs/decisions/0001-positioning.md)).

## Status
M0 (spike) is closed: findings in `docs/notes/foundationmodels.md`, experiments kept as
characterization tests in `Tests/`. M1 is done: `FakeModel`, `AvailabilityScript` and the
example app in `Examples/TokenSpeed`. M2 is done: `Cassette` records and replays text and
structured output (decision 0005), from the on-device model and from Private Cloud Compute
(PCC needs a signed app to record: `docs/guides/recording-private-cloud-compute.md`). M3 is
done: Apple's `Evaluations` runs from tapes in CI (`docs/guides/evaluations-in-ci.md`).
`Examples/PickTwo` exercises all of it.

M4 (drift, decision 0006, accepted) works and is waiting for a real model change, its "done
when". macOS 27.2 → 27.2.1 kept the on-device model. The first change will probably come from
PCC, whose model can change on Apple's servers with no OS update: checking it means running
`Drift.check(tape:on: PrivateCloudComputeLanguageModel())` inside a signed app.
`Examples/PickTwo/RecorderHost` records PCC but has no drift mode yet, and the `assay` command
only asks the on-device model. After every OS update: `scripts/test.sh after-update`.

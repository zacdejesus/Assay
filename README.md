# Assay 🧪

**The memory and regression detector for Apple's language models.**

Apple updates its on-device model without asking you, and only one version lives on a device
at a time. If your AI feature gets worse after an update, the old behaviour is gone, unless
someone recorded it.

Assay records what the model answered, replays it offline, and tells you what changed.

> 🚧 **Status: early.** The M0 spike is done and its findings are below. The library itself
> starts in M1, so there is nothing to add as a dependency yet.

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

## Roadmap

| Milestone | What | Status |
|---|---|---|
| M0 | Spike: can I plug into Apple's protocol at all? | ✅ done |
| M1 | `FakeModel` and availability simulation (v0.1) | next |
| M2 | Cassette: record once, replay with provenance (v0.2) | |
| M3 | Bridge to Apple's `Evaluations`, offline (v0.3) | |
| M4 | Drift report (v0.4) | |
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

I design and write the library code myself and use AI as a reviewer. The working agreement
is in [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE).

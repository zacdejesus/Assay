# Assay 🧪

**Test your AI features like real code.** A Swift library for testing Apple
FoundationModels and cloud-LLM features — deterministically, offline, and free.

> 🚧 **Status: early, design-first.** I'm building this from scratch to learn (see
> [CLAUDE.md](CLAUDE.md)). The API below is the design I'm building *toward* — not
> something that works yet.

## The problem

You add an AI feature with Apple's `FoundationModels` (or a cloud LLM). Then you try to
test it:

- on-device output is **non-deterministic** and slow,
- cloud calls **cost money and flake** in CI,
- and you can't even test what your UI does when Apple Intelligence is **unavailable**.

`promptfoo` / `deepeval` are Python. `swift-snapshot-testing` is for views. Nothing in
Swift is AI-native. That's the gap Assay aims at.

## The idea (target design)

**Simulate availability — so your fallback UI finally becomes testable:**

```swift
let model = MockModel(availability: .unavailable(.deviceNotEligible))
// drive your view model with `model`, then assert it shows the manual fallback
```

**Record once, replay forever — deterministic, offline, free:**

```swift
// record from the real model locally, commit the tape, and let CI replay it
let model = Cassette("recipe", recording: liveModel, mode: .auto)
let steps = try await model.respond(to: "3 steps to cook pasta")
```

## Roadmap

- **v0.1** — `MockModel` + availability simulation · `Cassette` record/replay
- **v0.2** — deterministic matchers · on-device `#judge` (binary pass/fail + critique)
- **v0.3** — eval suites · CI pass/fail gate · `pass@k` / `pass^k` · cost & latency
- **v0.4** — judge calibration (precision/recall against my own labels)
- **v0.5+** — agents / tool-call trajectories · GitHub Action · OpenTelemetry export

## What Assay is *not*

- Not a provider abstraction — it builds on top of things like AnyLanguageModel.
- Not a hosted dashboard. Not a prompt manager.

## How this is built

A personal **learning project**: I write all the code myself; AI assists only as a mentor
and reviewer. The working agreement lives in [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE).

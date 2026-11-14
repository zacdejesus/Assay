# 0001: Positioning: complement Apple, own what Apple won't do

- **Status:** Accepted (2026-09-22)
- **Date:** 2026-09-22
- **Context doc:** [prior-art.md](../prior-art.md) (2026-09-21 snapshot)

## Context

Assay was designed (README, roadmap v1) for the iOS 26 world: invent a seam to mock the
model, record/replay it, then build matchers, an LLM judge and eval suites.

At WWDC26 Apple shipped:
- a public `LanguageModel` / `LanguageModelExecutor` protocol (OS 27), so any model,
  including a fake, can back a `LanguageModelSession`;
- the `Evaluations` framework: datasets, evaluators, model judges, Swift Testing trait,
  Xcode reports and run comparison.

History says first-party tools win when they need privileged access (compiler, OS, Xcode)
or are trivial for Apple to add: async/await vs. RxSwift/Combine, SPM vs. CocoaPods,
Swift Testing vs. Quick/Nimble. Third-party tools survive where Apple provides an
extension point but not the opinionated tool on top (URLProtocol → OHHTTPStubs/Replay;
XCTest → swift-snapshot-testing), or where Apple's incentives point the other way.
Counter-example to keep in mind: StoreKit Testing, where Apple *did* simulate its own service.

## Options

1. **Keep v1:** own seam + own evals. ❌ Duplicates Apple; loses on every axis.
2. **Pure utilities:** fake model + availability simulation only. ❌ Exactly what Apple can
   add as a checkbox next year.
3. **Complement Apple; own the recording/history/drift layer.** ✅

## Decision

Option 3. Assay is **the memory and regression detector for Apple's language models**:
- builds on Apple's `LanguageModel` protocol (no own seam);
- cassettes (recorded, versioned, with provenance) are the core mechanism;
- feeds Apple's `Evaluations` so they run offline / in CI instead of re-implementing them;
- the headline feature is **drift detection across Apple model versions**, which goes
  against Apple's incentives to build;
- fake model and availability simulation stay as small utilities, accepted as disposable.

Every future feature passes the filter: *could Apple ship it as a checkbox, and would it
want to?* Effort goes where either answer is "no".

## Consequences

- ➕ Smaller surface; no fight with Apple; a niche that grows every time Apple ships a model.
- ➕ Clear story: "Apple changed your model. Here's what broke."
- ➖ Requires OS 27+ (probably; confirm in M0).
- ➖ Depends on unverified facts: can an executor wrap `SystemLanguageModel`? Does
  `Evaluations` run from the command line? Is there a model-version identifier? If M0
  answers "no" to the first, recording moves to the session level (worse ergonomics, same
  positioning).
- ➖ Small niche today (apps shipping on-device AI that care about testing).
- 📝 README roadmap must be rewritten to match.

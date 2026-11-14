# 0002: Minimum OS 27

- **Status:** Accepted (2026-11-07). Drafted by Claude from the M0 results, accepted by Alejandro.
- **Context doc:** [notes/foundationmodels.md](../notes/foundationmodels.md)

## Context

Everything Assay is built on exists only on OS 27: the `LanguageModel` / `LanguageModelExecutor`
protocols, `LanguageModelSession(model:)` for custom models, `Transcript.Response.assetIDs` /
`metadata` (provenance), and the `Evaluations` framework.

## Options

1. **OS 27+ only.** One code path, no `@available` noise.
2. **OS 26 + 27**, with an own seam (or AnyLanguageModel) on 26. Doubles the work, and on 26 there
   is no supported way to back a session with a fake model or to read model provenance.

## Decision

Option 1: `platforms: [.macOS("27.0"), .iOS("27.0")]` in `Package.swift`.

## Consequences

- ➕ The whole API surface is available without availability checks.
- ➖ An app whose deployment target is below 27 can't add Assay to its test target as-is.
  Open question: does that matter in practice, given tests usually run on a recent simulator?
  Revisit if a real user hits it.
- ➖ visionOS and watchOS are left out for now (add when there's a reason).

# Changelog

All notable changes to Assay are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com), and the project aims to follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- Project foundation: README, MIT license, `.gitignore`, and the AI working
  agreement (`CLAUDE.md`).
- Roadmap v2, the positioning decision (0001) and a prior-art snapshot.
- `Package.swift` (OS 27+, decision 0002) and the M0 spike: Experiments A and B as
  characterization tests, with findings in `docs/notes/`.
- Experiment C: greedy and fixed-seed sampling are repeatable on the on-device model;
  `assetIDs` and `jsonString` need normalising before comparison.
- Model canary test, baseline recording and comparison (`Baselines/`), and `scripts/test.sh`.
- `FakeModel`: a scripted `LanguageModel` for unit tests, with text, chunked, JSON and failing
  responses, simulated latency, a per-request closure and a call log (decision 0003).
- CI: unit tests on GitHub Actions, on a runner without Apple Intelligence.
- `AvailabilityScript`: a scripted sequence of `SystemLanguageModel.Availability` values for
  testing fallback screens and transitions, without importing Assay in app code (decision 0004).
- Example app `Examples/TokenSpeed`: tokens per second of the on-device model, with a fallback
  screen tested through `AvailabilityScript` and measuring tested through `FakeModel`.
- `Cassette`: records a model's answers to `__Cassettes__/<name>.json` and replays them
  without the model. Matches by request, fails loudly on a mismatch, never records in CI,
  stores provenance (decision 0005). Tape format v1: text and structured output.
- A tape recorded from the on-device model, replayed in CI (`RecordedTapeTests`).
- Apple's `Evaluations` from tapes: an evaluation with a model judge runs under `swift test`
  with no live model, and a tampered tape makes it fail. Guide in `docs/guides/`.
- Drift report: `Drift.check` asks the current model a tape's requests again and classifies
  each case; `Drift.compare` compares two tapes; the `assay` command prints a Markdown report.
  Tapes replaced by a different model's answers are kept under `generations/` (decision 0006).
- `CassetteError.missingEntitlement`: recording from Private Cloud Compute in a process without
  its entitlement (`swift test`, command-line tools) now says so and what to do, instead of an
  unnamed `LanguageModelError`. Guide in `docs/guides/recording-private-cloud-compute.md`.

### Changed
- README rewritten to match roadmap v2.
- Experiment A: an empty response throws `LanguageModelError.unsupportedTranscriptContent`
  since macOS 27.2 (was `GeneratedContent.ParsingError`).

_M1 is complete. M2 (cassettes), M3 (Evaluations) and M4 (drift) are in progress._

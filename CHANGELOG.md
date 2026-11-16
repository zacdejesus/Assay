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

### Changed
- README rewritten to match roadmap v2.
- Experiment A: an empty response throws `LanguageModelError.unsupportedTranscriptContent`
  since macOS 27.2 (was `GeneratedContent.ParsingError`).

_M1 is in progress: availability simulation is still to come._

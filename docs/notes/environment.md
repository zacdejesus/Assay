# Environment

> Checked 2026-11-07. Re-check after any OS or Xcode update.

| What | Value |
|---|---|
| Mac | Apple M4 (Apple Intelligence eligible) |
| macOS | 27.0.1 (26A434). Was 26.6.2 on 2026-09-22. |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4 (swiftlang-6.4.0.34.1), SwiftPM 6.4.0-dev |
| Apple Intelligence | Enabled on this Mac |
| iOS simulator runtimes | 18.6, 26.2, 26.4, 27.0 (×2), 27.1 |
| SDK used for API checks | `iPhoneSimulator27.1.sdk`, `FoundationModels.swiftinterface` |

## What runs where

- **`swift test` on this Mac runs OS 27 APIs** (`LanguageModel`, custom executors), because the
  host is macOS 27. No simulator needed for M0–M2.
- **The real on-device model runs from `swift test`** on this Mac (Experiment B got a live answer
  in about 1–2 s). The open question about the iOS 27 simulator on a macOS 26 host no longer
  matters.
- **`import Evaluations` compiles and links under `swift test`.** The framework ships in
  `MacOSX.platform/Developer/Library/Frameworks` (next to XCTest), which SwiftPM already puts on
  the framework search path. Running a full `Evaluation` from the command line is still
  unverified (M3).

## Still unverified

- Does the fake model (Experiment A) pass with Apple Intelligence **off**? Almost certainly
  (it never touches `SystemLanguageModel`), but the proof is a run with it disabled, or CI.
- Swift Testing prints `Target Platform: arm64e-apple-macos14.0` although the package targets
  macOS 27. Tests using OS 27 APIs pass, so it doesn't block anything. Cause unknown.

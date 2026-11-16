# Environment

> Checked 2026-11-15. After any OS or Xcode update, follow the [update routine](#update-routine).

| What | Value |
|---|---|
| Mac | Apple M4 (Apple Intelligence eligible) |
| macOS | 27.2 (26B123), seen 2026-11-15. Was 27.0.1 (26A434) on 2026-11-07 and 26.6.2 on 2026-09-22. |
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

## CI

GitHub Actions runs `scripts/test.sh` on every pull request and on pushes to `main`
(`.github/workflows/tests.yml`), on the `xcode-27` runner image. Checked 2026-11-16: the runner
had macOS 27.2 (26B123) and Xcode 27.1, and reported the on-device model as
`unavailable(deviceNotEligible)`.

That answers a question that was open here: **the unit tests, `FakeModel` included, pass on a
machine without Apple Intelligence.** The live tests don't run in CI.

## Still unverified

- Swift Testing prints `Target Platform: arm64e-apple-macos14.0` although the package targets
  macOS 27. Tests using OS 27 APIs pass, so it doesn't block anything. Cause unknown.

## Model versions seen on this Mac

The model assets come from `Transcript.Response.assetIDs`. Only the main model asset is listed;
the tokenizer and the draft model have their own versions.

| Seen | macOS | Main model asset |
|---|---|---|
| 2026-11-07 | 27.0.1 (26A434) | `...fm_api_generic_3b?variant=generic_sparse_16.1.0.13.103120,0` |
| 2026-11-15 | 27.2 (26B123) | `...fm_api_generic_3b?variant=generic_sparse_16.1000.0.13.103404,0` |

The system and the model changed between the two checks. Nothing was recorded from the first
model, so how it answered can't be compared any more. Baselines exist from the second one on.

## Update routine

A device holds one version of the model. Once an update replaces it, the old one can't be asked
again. So:

**Before installing an OS update**

```sh
scripts/test.sh before-update   # records what the current model answers into Baselines/
```

Commit the new file in `Baselines/`. Keep automatic OS updates off, so the model changes when
you choose.

**After installing it**

```sh
scripts/test.sh after-update    # canary, full live suite, new baseline, comparison
```

Then:
- If the canary failed, the model changed: put the new IDs in `knownAssetIDs`
  (`Tests/AssayTests/ModelCanaryTests.swift`).
- If a characterization test failed, the framework's behavior changed: update the test and
  write down what changed in [foundationmodels.md](foundationmodels.md).
- Add a row to the table above and update the versions at the top of this file.

## Running the tests

| Command | What it runs | Needs the model |
|---|---|---|
| `scripts/test.sh` | Unit tests | No |
| `scripts/test.sh live` | Everything | Yes |
| `scripts/test.sh greedy` | Experiment C: repeatability of greedy and seeded sampling (about 3 minutes) | Yes |
| `scripts/test.sh canary` | Has the model changed since the last check? | Yes |
| `scripts/test.sh record` | Writes a baseline for the current model | Yes |
| `scripts/test.sh compare` | Compares the two most recent baselines | No |

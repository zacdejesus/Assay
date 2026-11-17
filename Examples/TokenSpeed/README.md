# TokenSpeed

An iOS and macOS app that shows how fast the on-device model generates: tokens per second, as
a big number, while the answer streams. When the model can't be used, it says why instead.

It is Assay's example app: small enough to read in a few minutes, and it has the two things
that are hard to test in an app built on FoundationModels.

| What the app does | How it's tested |
|---|---|
| Shows a fallback screen when the device isn't eligible, Apple Intelligence is off, or the model is still downloading. Moves on when the model becomes available. | `AvailabilityScript` |
| Streams a response and measures it. Shows the error when the request fails. | `FakeModel` |

## Layout

```
TokenSpeed.xcodeproj     the app target: one file, App/TokenSpeedApp.swift
TokenSpeedCore/          a Swift package with everything else
  Sources/               SpeedTest (logic), SpeedMeter (arithmetic), Fallback, ModelAssets,
                         SpeedTestView
  Tests/                 the tests, which import Assay
```

**The app doesn't import Assay.** `SpeedTest` takes two closures written with Apple's types,
and the app uses their defaults:

```swift
SpeedTest(
    availability: { SystemLanguageModel.default.availability },
    makeSession: { LanguageModelSession() }
)
```

A test passes its own:

```swift
let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
let model = FakeModel(.chunks(["The ", "keeper ", "waved."]))
let test = SpeedTest(availability: script.next, makeSession: { LanguageModelSession(model: model) })
```

## Run it

Open `TokenSpeed.xcodeproj` in Xcode 27 and run on a Mac, or on an iPhone or iPad with Apple
Intelligence. To run on a device, set your team under Signing & Capabilities. The app also
builds for the iOS simulator; running it there hasn't been checked.

## Test it

```sh
scripts/test.sh example      # from the repository root
```

20 tests, about a tenth of a second, no Apple Intelligence needed. They also run in CI.

## What the numbers mean

- **Tokens per second**: output tokens after the first report, divided by the time since it.
  The wait for the first tokens is left out.
- **The small grey lines** under the numbers are the model's asset identifiers, as the
  framework reports them. Apple's API has no model name; this is what identifies the model
  and its version.
- **First tokens**: time from sending the request to the first report of output tokens. The
  model reports usage in batches (about 10 tokens at a time on macOS 27.2), so this is a
  little later than the very first token. The first run after launch is slower.

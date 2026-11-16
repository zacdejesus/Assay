# 0004: Availability simulation

- **Status:** Accepted (2026-11-16). Options drafted by Claude; the choice (option C, repeat the
  last value) was made by Alejandro.
- **Context docs:** [roadmap M1](../roadmap.md), [notes/foundationmodels.md](../notes/foundationmodels.md),
  [0003: FakeModel public API](0003-fakemodel-api.md)
- **Code:** `Sources/Assay/AvailabilityScript.swift`, `Tests/AssayTests/AvailabilityScriptTests.swift`

## Context

An app has to show something different when the on-device model can't be used: the device isn't
eligible, Apple Intelligence is off, or the model is still downloading. The app reads that from
`SystemLanguageModel.default.availability`, which returns whatever the machine running the test
has. So the fallback screens can't be reached from a test.

M0 found that availability is **not** on the `LanguageModel` protocol; it exists only on the
concrete model types. `FakeModel` therefore can't simulate it. The app has to read availability
through something a test can replace. The question is who owns that something.

`SystemLanguageModel.Availability` is a public, frozen enum (`Equatable`, `Sendable`), so a
test can build any value of it.

## Options

1. **Assay defines the protocol.** The app's production code imports Assay and reads
   availability through an Assay type. ❌ A testing library ends up in the shipped binary.
2. **Two modules.** A tiny runtime module with the protocol, and the test module. ❌ Solves
   option 1, but adds package structure for a few lines that Apple could make obsolete at any
   time (roadmap: Apple risk high for M1).
3. **The app owns the seam; Assay supplies the script.** The app declares one closure with
   Apple's own type. Assay gives tests a scripted sequence to put in it. ✅ Assay stays out of
   production code.

## Decision

Option 3.

```swift
// App: no Assay import
var availability: () -> SystemLanguageModel.Availability = {
    SystemLanguageModel.default.availability
}

// Test
let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
viewModel.availability = script.next
```

| Question | Choice |
|---|---|
| What happens when the script is used up? | **The last value repeats.** Availability is a state, and a view may read it any number of times. This is the opposite of `FakeModel`, where running out is an error. |
| Can a script be empty? | **No.** The variadic initializer takes at least one value; the array initializer has a precondition. |
| Value or reference type? | **A `final class`**, `Sendable`, with the position behind a `Mutex`. The script has identity: every reader advances the same sequence. |
| What can a test assert? | `readCount`, and `isFinished` (every scripted value was returned at least once). |

## Not in v0.1

- `PrivateCloudComputeLanguageModel.Availability`: a different type with its own reasons. The
  same pattern would apply.
- Advancing by something other than a read (time, or an explicit step). A view that reads
  availability twice per render consumes two steps; a test that needs exact control over that
  can script the value twice.
- Observation: nothing notifies the app that availability changed. The app polls, as it does
  with the real API.

## Consequences

- ➕ Nothing from Assay ships in an app.
- ➕ Transitions (`modelNotReady` → `available`) are testable, which is the part that is hard
  to reproduce by hand.
- ➖ The app has to write the closure itself, and Assay can't check that it did.
- ➖ Little code. If Apple ships an availability override, this type goes away, and that is fine.

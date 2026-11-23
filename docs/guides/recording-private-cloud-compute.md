# Record Private Cloud Compute with Assay

`PrivateCloudComputeLanguageModel` is a `LanguageModel`, so a cassette records it like any
other model:

```swift
let cassette = try Cassette("coach-cloud", recording: PrivateCloudComputeLanguageModel())
let session = LanguageModelSession(model: cassette.model)
```

Replaying the tape needs nothing: no network, no quota, no entitlement. Recording it is the
hard part.

## Why recording fails under `swift test`

PCC needs the `com.apple.developer.private-cloud-compute` entitlement. Apple assigns it to a
developer account, and it reaches a binary only through a provisioning profile of an App ID with
the Private Cloud Compute capability ([Accessing Private Cloud
Compute](https://developer.apple.com/private-cloud-compute)).

`swift test` runs tests in a process you don't sign, and a command-line tool can't carry a
provisioning profile. Without the entitlement, PCC still reports `available` and a quota below
the limit, and then fails every request with `ModelManagerError` 1046 inside an unnamed
`LanguageModelError` (macOS 27.2.1, seen under `swift test` and in an unsigned binary). Inside
an app the same missing entitlement is worse: FoundationModels traps instead of throwing.

Assay recognizes that failure and throws `CassetteError.missingEntitlement`, which points here.

## Where to record from

The recording has to run inside an app signed with the capability. Record there, commit the
tapes, and replay them anywhere, CI included.

| Where | Status | Notes |
|---|---|---|
| A test hosted in your iOS app, on an iPhone | Works (the app calls PCC on device) | `#filePath` doesn't exist on the phone: pass `directory:` inside the app's container and copy the tapes off with `xcrun devicectl`, or print them to the log |
| A test hosted in your iOS app, in the simulator with signing on | Not verified | The simulator writes to the Mac's disk, so tapes land next to the test as usual |
| **A small macOS app with the capability** | **Works** (2026-11-23, macOS 27.2.1, development signing) | The simplest on a Mac: see below |

## Recording from a small macOS app

Verified 2026-11-23: a development-signed Mac app with the capability called PCC (2.2 s) and a
cassette recorded six structured requests from it; `swift test` then replayed them with `CI` set.

1. In Xcode, a new macOS App target with its own bundle ID (for example
   `com.example.recorder`), automatic signing, your team.
2. **Signing & Capabilities → + Capability → Private Cloud Compute.** It is offered when your
   account has the entitlement. Adding it enables the capability on the App ID; `xcodebuild`
   alone can't, and fails with "Entitlement … not found and could not be included in profile".
3. The first development build of a Mac app registers the Mac as a device in your account
   (`-allowProvisioningDeviceRegistration` from the command line).
4. Add your package (or its sources) and run the code that makes the requests, with each
   cassette's `directory:` pointing at your test's `__Cassettes__`. A plain executable target
   with no window is enough; launch `YourApp.app/Contents/MacOS/YourApp`.
5. Commit the tapes. Tests replay them with no entitlement.

What a PCC tape records: PCC's own `assetIDs` (`com.apple.fm.language.instruct_server_v2…`) and
the server's build as `systemVersion` (`6B85`), not your Mac's. **The PCC model can change on
Apple's servers without any update on your machine**. Drift catches it the same way, by
`assetIDs`, but only when it runs inside the signed app (`Drift.check(tape:on:
PrivateCloudComputeLanguageModel())`): the `assay` command asks the on-device model.

## What doesn't work

- Signing a test runner or a command-line tool with the entitlement and no profile: macOS
  refuses restricted entitlements without a provisioning profile.
- Recording in CI: hosted runners have no Apple Intelligence and no entitlement, and Assay never
  records when `CI` is set anyway.

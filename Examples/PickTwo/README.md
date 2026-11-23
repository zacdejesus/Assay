# PickTwo

A small feature built the way many Foundation Models features are: give the model a numbered
list, get back two items that go together, each with three suggestions. Two domains:

- **Gym:** from the user's muscle groups, two for today's session, with 3 exercises each.
- **Meals:** from the ingredients at home, two of one cuisine, with 3 dishes each.

The example shows how to test it with Assay, and what testing it found.

## What you need

| To | You need |
|---|---|
| Replay everything (`swift test`) | macOS 27 and Xcode 27. No model, no network. Works in CI |
| Record the on-device tapes, run the experiment | A Mac with Apple Intelligence on |
| Record the Private Cloud Compute tapes | An account with the [Private Cloud Compute entitlement](https://developer.apple.com/private-cloud-compute) (if your app uses PCC, you have it) |

## Run it

```sh
swift test                                               # replays the tapes, about 0.1 s
ASSAY_CASSETTE=record swift test                         # records the on-device tapes again
PICKTWO_EXPERIMENT=1 swift test --filter "Experiment/gym"     # live experiment, a few minutes
PICKTWO_EXPERIMENT=1 swift test --filter "Experiment/meals"
PICKTWO_EXPERIMENT=1 swift test --filter "Experiment/gymDetails"
swift run --package-path ../.. assay drift Tests/PickTwoTests/__Cassettes__
swift run --package-path ../.. assay drift Tests/PickTwoTests/__Cassettes__/random-sampling
```

## What is in it

| | |
|---|---|
| `Sources/PickTwo/Domain.swift` | The two domains: categories, instructions, prompt |
| `Sources/PickTwo/Suggester.swift` | The feature: two schemas, two strategies, and the code around the model |
| `Sources/PickTwo/Cases.swift` | Twelve lists a user could have, shared by every test |
| `Tests/PickTwoTests/TapeTests.swift` | The recommended setup from tapes: on-device, PCC, and random sampling |
| `Tests/PickTwoTests/EvaluationTests.swift` | The same as an Apple `Evaluation`, with code metrics |
| `Tests/PickTwoTests/Experiment.swift` | The live experiment below |
| `RecorderHost/` | A small signed Mac app that records the PCC tapes |

The recommended setup: **code chooses the category, and the schema copies each item's name
before its suggestions.**

## What testing found

From one run on macOS 27.2.1 (on-device model assets `16.1000.0.13.103404`), 5 samples per case,
the app's random sampling (temperature 0.7). Your numbers will differ: sampling is random and
the model changes with OS updates. The procedure is what reproduces.

"Due category" is the one code picks from the history: the category of the least recently used
item that has a partner in the list.

| Gym (30 samples each) | Two picks | Coherent | Due category | Categories chosen |
|---|---|---|---|---|
| Label first, model chooses | 25 | 17/25 | 6 | push 15, legs 1, pull 1 |
| The same, table reversed in the instructions | 8 | 8/8 | 7 | legs 8 |
| Name first, model chooses | 25 | 16/25 | 5 | push 15, legs 1 |
| **Name first, code chooses** | **30** | **30/30** | **30** | pull 15, legs 10, push 5 |

| Meals (30 samples each) | Two picks | Coherent | Due category | Categories chosen |
|---|---|---|---|---|
| Label first, model chooses | 30 | 25/30 | 15 | italian 15, japanese 5, mexican 5 |
| The same, table reversed in the instructions | 30 | 30/30 | 15 | japanese 30 |
| Name first, model chooses | 30 | 25/30 | 15 | italian 15, mexican 5, japanese 5 |
| **Name first, code chooses** | **30** | **30/30** | **30** | japanese 15, mexican 10, italian 5 |

**1. The model takes the first category of the instructions, not the best one.** The
instructions list the categories as a table ("push: chest, shoulders, triceps; pull: …").
Whenever the first one had items, the model took it: push in gym, Italian in meals, whatever the
history said. Reversed, the table's new first category won instead (legs, Japanese). In gym it
then picked Legs twice, which leaves one pick. With no item of the first category, it took
another one and paired across categories (Back + Abs, Pasta + Miso).

**2. Deciding the category in code fixes it.** Code knows the categories and the history;
handed only the due category's items, the model did what it does well: two items and their
suggestions. 60/60 coherent and due, in both domains.

**3. Copying the name before the suggestions helps the suggestions, not the choice.** With code
choosing, gym exercises under the group they train went from 23/30 to 28/30
(`Experiment/gymDetails`, a keyword check). The typical miss was "Back Squats" under Back (7
samples, 2 with the name copied). It made no difference to which items were picked.

**4. A drift report on randomly sampled tapes is noise.** With the same model, minutes apart,
the 24 greedy requests came back unchanged and the 12 randomly sampled ones all changed. That's
why the tests record with greedy sampling, and why `random-sampling/` exists: to show the
difference.

## Recording Private Cloud Compute

PCC needs the `com.apple.developer.private-cloud-compute` entitlement, which `swift test` can't
have (Assay says so: `CassetteError.missingEntitlement`). `RecorderHost` is a Mac app with only
that entitlement. It records one tape per case into `Tests/PickTwoTests/__Cassettes__`, and
`swift test` replays them like the others. Details:
[recording-private-cloud-compute.md](../../docs/guides/recording-private-cloud-compute.md).

1. Create `RecorderHost/Local.xcconfig` (git-ignored) with your team and a bundle ID of yours:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   RECORDER_BUNDLE_ID = com.yourname.picktwo.recorder
   ```
2. Open `RecorderHost/RecorderHost.xcodeproj` once in Xcode: target RecorderHost, Signing &
   Capabilities, + Capability, **Private Cloud Compute**. This enables it on your App ID;
   `xcodebuild` can't.
3. Build and run:
   ```sh
   cd RecorderHost
   xcodebuild -scheme RecorderHost -derivedDataPath build -allowProvisioningUpdates \
     -allowProvisioningDeviceRegistration build
   build/Build/Products/Debug/RecorderHost.app/Contents/MacOS/RecorderHost
   ```
   The first build registers your Mac as a device in your account.

The PCC tapes record PCC's own model version (`instruct_server_v2` asset IDs, the server's
build): it can change on Apple's servers with no update on your Mac. In this run PCC answered
every case with a coherent pair of the due category; that's the recommended setup, so it says
little about PCC on its own.

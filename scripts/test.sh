#!/bin/sh
# How to run Assay's tests.
#
#   scripts/test.sh                 unit tests only: fast, no model needed
#   scripts/test.sh example         the example app's tests (Examples/TokenSpeed): fast, no model needed
#   scripts/test.sh live            everything, including the tests that call the real model
#   scripts/test.sh greedy          Experiment C: is greedy (and seeded) sampling repeatable?
#   scripts/test.sh canary          has the on-device model changed since the last check?
#   scripts/test.sh record          record what the current model answers into Baselines/
#   scripts/test.sh rerecord        record the committed tapes again (Tests/AssayTests/__Cassettes__)
#   scripts/test.sh drift           ask the current model the tapes' requests again; report what changed
#   scripts/test.sh drift-update    the same, and keep the new answers (old tapes go to generations/)
#   scripts/test.sh compare         compare the two most recent baselines
#
#   scripts/test.sh before-update   run BEFORE installing an OS update
#   scripts/test.sh after-update    run AFTER installing it
#
# The live modes need a Mac with Apple Intelligence enabled.

set -eu
cd "$(dirname "$0")/.."

case "${1:-unit}" in
  unit)
    swift test
    ;;
  example)
    swift test --package-path Examples/TokenSpeed/TokenSpeedCore
    ;;
  live)
    ASSAY_LIVE=1 swift test
    ;;
  greedy)
    ASSAY_LIVE=1 swift test --filter ExperimentC
    ;;
  canary)
    ASSAY_LIVE=1 swift test --filter ModelCanary
    ;;
  record)
    ASSAY_RECORD=1 swift test --filter recordBaseline
    ;;
  rerecord)
    ASSAY_CASSETTE=record swift test --filter 'RecordedTape|EvaluationsBridge'
    ;;
  drift)
    swift run -q assay drift Tests/AssayTests/__Cassettes__ --report drift-report.md
    ;;
  drift-update)
    swift run -q assay drift Tests/AssayTests/__Cassettes__ --update --report drift-report.md
    ;;
  compare)
    ASSAY_COMPARE=1 swift test --filter compareLatestBaselines
    ;;
  before-update)
    # The model on this machine is about to be replaced. Keep what it answers.
    sw_vers
    "$0" record
    echo
    echo "Baseline recorded. Commit Baselines/ and then install the update."
    ;;
  after-update)
    sw_vers
    echo "== 1/5 canary (a failure here means the model changed: expected after an update)"
    "$0" canary || true
    echo "== 2/5 full suite, live (failures here are behavior changes in the framework)"
    "$0" live || true
    echo "== 3/5 drift report: the tapes' requests, asked again (saved to drift-report.md)"
    "$0" drift || true
    echo "== 4/5 new baseline"
    "$0" record
    echo "== 5/5 comparison with the previous baseline"
    "$0" compare
    echo
    echo "Read drift-report.md. To keep the new model's answers as the tapes (the old ones"
    echo "move to generations/): scripts/test.sh drift-update"
    echo "Next: update knownAssetIDs in Tests/AssayTests/ModelCanaryTests.swift if the canary"
    echo "failed, and add the new versions to docs/notes/environment.md."
    ;;
  *)
    sed -n '2,19p' "$0"
    exit 2
    ;;
esac

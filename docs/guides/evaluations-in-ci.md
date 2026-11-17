# Run Apple's Evaluations in GitHub Actions with Assay

Apple's `Evaluations` framework scores a model feature over a dataset. It needs a live model
twice: for the answers being evaluated, and for a model judge if you use one. Hosted CI
machines don't have Apple Intelligence, so an evaluation can't run there.

With Assay, both come from tapes recorded once on your Mac.

Checked on macOS 27.2 with Xcode 27.1 (2026-11-16). The working example is
[`Tests/AssayTests/EvaluationsBridgeTests.swift`](../../Tests/AssayTests/EvaluationsBridgeTests.swift).

## What was verified

- `import Evaluations` works in a SwiftPM test target, and `Evaluation.run()` works under
  `swift test`. No Xcode UI is needed.
- A `ModelJudgeEvaluator` takes any `LanguageModel` as its judge, so it takes a cassette's.
  Its requests are structured (a schema with a value and a rationale per dimension), which
  tape format v1 stores.
- Replayed from tapes, the example evaluation (3 samples, one code metric, one judged
  dimension) takes about 0.01 s.

## 1. Give the evaluation its models from outside

```swift
import Assay
import Evaluations
import FoundationModels

struct CapitalsEvaluation: Evaluation {
    var model: Cassette.Model   // the model being evaluated
    var judge: Cassette.Model   // the model that scores it

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let session = LanguageModelSession(model: model, instructions: "Answer in one short sentence.")
        let response = try await session.respond(to: sample.prompt)
        return ModelSubject(value: response.content)
    }

    var evaluators: Evaluators {
        Evaluator<ModelSample<String>> { sample, subject in
            subject.value.contains(sample.expected ?? "") ? correct.passing() : correct.failing()
        }
        ModelJudgeEvaluator<ModelSample<String>>(judge: judge, dimensions: [concise])
    }
    // dataset, aggregateMetrics…
}
```

There is no adapter. `subject(from:)` is your code, so it can build its session over any
model.

## 2. Run it in a test, with one tape per model

```swift
@Test func capitals() async throws {
    let subject = try Cassette("evaluation-capitals")
    let judge = try Cassette("evaluation-capitals-judge")

    let result = try await CapitalsEvaluation(model: subject.model, judge: judge.model).run()

    #expect(result.errors.evaluatorFailureCount == 0)
    #expect(result.aggregateValue(.mean(of: correct)) >= 0.9)
}
```

Use two tapes. The subject and the judge are different roles, and you will want to record
one again without the other.

## 3. Record on your Mac, commit the tapes

```sh
swift test --filter capitals        # first run: records both tapes
git add Tests/**/__Cassettes__
```

In `Package.swift`, add `exclude: ["__Cassettes__"]` to the test target.

## 4. CI

```yaml
jobs:
  test:
    runs-on: xcode-27        # macOS 27 with Xcode 27
    steps:
      - uses: actions/checkout@v4
      - run: swift test
```

GitHub Actions sets `CI`, and with `CI` set Assay never records: a missing tape or a request
that isn't on the tape fails the run.

## What this does and doesn't tell you

- **It is a regression gate, not a measurement.** A replayed evaluation gives the same score
  every time. It tells you that your prompts, parsing and scoring code still produce the same
  result from the same model answers. It says nothing about variance, and nothing about a
  newer model. For that, record again and compare (roadmap M4).
- **A changed answer invalidates the judge's tape.** The judge's request contains the answer
  it scores. If the answer changes, the judge's tape has no recording for it, and the
  evaluator fails instead of returning a stale score. Record both tapes again.
- **Tapes are recorded with greedy sampling** unless your code chooses a mode, so the recorded
  answer is the model's most likely one, not a typical sample.
- **Small datasets prove little.** Three samples at 100% is an example, not evidence.

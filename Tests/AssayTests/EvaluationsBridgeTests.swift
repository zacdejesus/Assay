// M3: Apple's Evaluations framework, fed from tapes.
//
// Evaluations needs a live model: the subject's answers come from one, and so do a model
// judge's scores. Here both come from cassettes, so the evaluation runs with `swift test`
// on machines without Apple Intelligence, CI included.
//
// No adapter is involved. An `Evaluation` produces its subject in its own code, and
// `ModelJudgeEvaluator` takes any `LanguageModel` as judge: both accept `cassette.model`.
//
// To record the tapes again, on a Mac with Apple Intelligence:  scripts/test.sh rerecord

import Assay
import Evaluations
import Foundation
import FoundationModels
import Testing

/// A small evaluation: does the feature answer with the right capital, briefly?
struct CapitalsEvaluation: Evaluation {
    static let correct = Metric("Correct")
    static let concise = ScoreDimension(
        "Conciseness",
        description: "Whether the answer is short and to the point.",
        scale: .passFail(
            passDescription: "One short sentence or less.",
            failDescription: "Longer than one short sentence."
        )
    )

    /// The model under evaluation.
    var model: Cassette.Model
    /// The model that scores conciseness.
    var judge: Cassette.Model

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: [
            ModelSample(prompt: "What is the capital of France?", expected: "Paris"),
            ModelSample(prompt: "What is the capital of Japan?", expected: "Tokyo"),
            ModelSample(prompt: "What is the capital of Peru?", expected: "Lima"),
        ])
    }

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let session = LanguageModelSession(model: model, instructions: "Answer in one short sentence.")
        let response = try await session.respond(to: sample.prompt, options: GenerationOptions(maximumResponseTokens: 60))
        return ModelSubject(value: response.content)
    }

    var evaluators: Evaluators {
        Evaluator<ModelSample<String>> { sample, subject in
            let expected = sample.expected ?? ""
            return subject.value.contains(expected)
                ? Self.correct.passing()
                : Self.correct.failing(rationale: "Expected \(expected)")
        }
        ModelJudgeEvaluator<ModelSample<String>>(judge: judge, dimensions: [Self.concise])
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.correct)
        aggregator.computeMean(of: Self.concise.metric)
    }
}

// Serialized: while recording, only one cassette can write a tape at a time.
@Suite("Evaluations bridge: Apple's Evaluations from tapes", .serialized)
struct EvaluationsBridgeTests {

    @Test("An evaluation with a model judge runs from tapes")
    func evaluationRunsFromTapes() async throws {
        let subject = try Cassette("evaluation-capitals")
        let judge = try Cassette("evaluation-capitals-judge")

        let result = try await CapitalsEvaluation(model: subject.model, judge: judge.model).run()

        #expect(result.errors.inferenceFailureCount == 0)
        #expect(result.errors.evaluatorFailureCount == 0)
        #expect(result.aggregateValue(.mean(of: CapitalsEvaluation.correct)) == 1)
        #expect(result.aggregateValue(.mean(of: CapitalsEvaluation.concise.metric)) == 1)
    }

    /// The other half of "done": the evaluation has to be able to fail. One recorded answer
    /// is changed to a wrong one, in a copy of the tape.
    @Test("A regression in the recorded answers makes the evaluation fail")
    func regressionIsCaught() async throws {
        let cassettes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Cassettes__")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("assay-evaluation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let original = try String(contentsOf: cassettes.appendingPathComponent("evaluation-capitals.json"), encoding: .utf8)
        let tampered = original.replacingOccurrences(of: "Paris", with: "Lyon")
        #expect(tampered != original)
        try tampered.write(to: scratch.appendingPathComponent("evaluation-capitals.json"), atomically: true, encoding: .utf8)

        let subject = try Cassette("evaluation-capitals", mode: .replay, directory: scratch)
        let judge = try Cassette("evaluation-capitals-judge", mode: .replay)
        let result = try await CapitalsEvaluation(model: subject.model, judge: judge.model).run()

        let correct = result.aggregateValue(.mean(of: CapitalsEvaluation.correct))
        #expect(abs(correct - 2.0 / 3.0) < 0.001)
        // The judge was never asked about the wrong answer, so its tape has no score for
        // it. That shows up as an evaluator failure, not as an invented score.
        #expect(result.errors.evaluatorFailureCount == 1)
    }
}

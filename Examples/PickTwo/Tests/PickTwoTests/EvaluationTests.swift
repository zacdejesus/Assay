// The feature as an Apple Evaluation, from a tape. Code metrics only: what this feature promises
// can be checked in code. For a model judge from tapes, see docs/guides/evaluations-in-ci.md.

import Assay
import Evaluations
import Foundation
import FoundationModels
import PickTwo
import Testing

struct PickTwoEvaluation: Evaluation {
    static let twoPicks = Metric("Two picks")
    static let coherent = Metric("Coherent")
    static let due = Metric("Least recent category")

    var model: Cassette.Model

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: Case.all.map { ModelSample(prompt: "\($0)") })
    }

    static func lookup(_ sample: ModelSample<String>) -> Case {
        // `prompt` is a `Prompt`; its description is the text.
        let text = String(describing: sample.prompt)
        return Case.all.first { text.contains("\($0)") }!
    }

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let c = Self.lookup(sample)
        let s = try await Suggester.suggest(c.items, in: c.domain, model: model)
        return ModelSubject(value: String(decoding: try JSONEncoder().encode(s), as: UTF8.self))
    }

    static func decode(_ subject: ModelSubject<String>) throws -> Suggestion {
        try JSONDecoder().decode(Suggestion.self, from: Data(subject.value.utf8))
    }

    var evaluators: Evaluators {
        Evaluator<ModelSample<String>> { _, subject in
            try Self.decode(subject).picks.count == 2 ? Self.twoPicks.passing() : Self.twoPicks.failing()
        }
        Evaluator<ModelSample<String>> { sample, subject in
            let c = Self.lookup(sample)
            return Score.coherent(try Self.decode(subject), in: c.domain) == true ? Self.coherent.passing() : Self.coherent.failing()
        }
        Evaluator<ModelSample<String>> { sample, subject in
            let c = Self.lookup(sample)
            let due = Selection.forToday(c.items, in: c.domain).first.flatMap(c.domain.category(of:))
            return Score.category(try Self.decode(subject), in: c.domain) == due ? Self.due.passing() : Self.due.failing()
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.twoPicks)
        aggregator.computeMean(of: Self.coherent)
        aggregator.computeMean(of: Self.due)
    }
}

@Suite("Evaluation")
struct EvaluationTests {
    @Test("The recommended setup scores from a tape")
    func scores() async throws {
        let result = try await PickTwoEvaluation(model: try Cassette("evaluation-ondevice").model).run()
        let scores = [PickTwoEvaluation.twoPicks, PickTwoEvaluation.coherent, PickTwoEvaluation.due]
            .map { result.aggregateValue(.mean(of: $0)) }
        print("EVALUATION two picks \(scores[0]) coherent \(scores[1]) least recent \(scores[2])")
        #expect(result.errors.inferenceFailureCount == 0)
        // With own names in the list ("Upper body", "Leftover chicken"), code still finds a
        // known pair, so every case is scorable. Pinned at what the recording got.
        #expect(scores == [1, 1, 1])
    }
}

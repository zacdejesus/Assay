// Experiment C: is the on-device model's output repeatable?
// M2 wants to record with greedy sampling so a tape reflects the model, not sampling luck,
// and M4 wants to read any difference between two recordings as a model change. Both assume
// that the same model, prompt and options give the same answer every time.
//
// Findings in docs/notes/foundationmodels.md. The tests below pin them as characterization
// tests: if a new OS or model changes any of it, the failing test names the assumption
// that broke.
//
// Live tests: they call the real model about 150 times, so they're opt-in and take a few
// minutes. Run them with
//   scripts/test.sh greedy        (or: ASSAY_LIVE=1 swift test --filter ExperimentC)

import Foundation
import FoundationModels
import Testing

// Serialized: the tests share one on-device model, and running them in parallel would
// add a variable the experiment doesn't control.
@Suite("Experiment C: is the output repeatable?", .serialized)
struct ExperimentCTests {

    /// Three kinds of request, because they may not behave the same way.
    enum Prompt: String, CaseIterable, Sendable {
        /// One expected word.
        case short
        /// Open-ended on purpose: if sampling varies anywhere, it shows here.
        case open
        /// Guided generation into a `@Generable` type.
        case structured

        var text: String {
            switch self {
            case .short: "What is the capital of France? Answer in one word."
            case .open: "Write a short paragraph, about 60 words, describing a walk through a forest in autumn."
            case .structured: "Describe a hiking trail in a pine forest."
            }
        }
    }

    /// How many times each request is sent.
    static let runCount = 20

    /// Bounds the cost of every call and keeps the conditions comparable.
    static let responseTokenLimit = 120

    /// The seeded condition: random sampling over the 50 most likely tokens, fixed seed.
    static let top = 50
    static let seed: UInt64 = 42

    static func options(_ sampling: GenerationOptions.SamplingMode?) -> GenerationOptions {
        GenerationOptions(samplingMode: sampling, maximumResponseTokens: responseTokenLimit)
    }

    /// The same request `runCount` times, one after another, each in a new session.
    static func runs(_ prompt: Prompt, _ sampling: GenerationOptions.SamplingMode?) async throws -> [Live.Run] {
        var runs: [Live.Run] = []
        for _ in 0..<runCount {
            runs.append(try await Live.respond(
                to: prompt.text,
                structured: prompt == .structured,
                options: options(sampling)
            ))
        }
        return runs
    }

    /// Where two strings first differ, as a character offset.
    static func firstDifference(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

    /// Prints the outcome of one condition, so it can be copied into the notes.
    static func report(_ label: String, _ prompt: Prompt, _ runs: [Live.Run]) -> Int {
        let outputs = Set(runs.map(\.output)).sorted()
        var line = "[Experiment C] \(label), \(prompt.rawValue) prompt: \(runs.count) runs, \(outputs.count) distinct"
        if outputs.count > 1 {
            line += ", first difference at character \(firstDifference(outputs[0], outputs[1]))"
        }
        print(line)
        return outputs.count
    }

    /// The control. With the default sampling the open prompt must give different answers.
    /// If it doesn't, this experiment can't detect variation, and "identical every time"
    /// for the other conditions would mean nothing.
    @Test(
        "Control: default sampling varies on an open prompt",
        .enabled(if: Live.isEnabled, "Live test: needs ASSAY_LIVE=1 and Apple Intelligence")
    )
    func defaultSamplingVaries() async throws {
        let runs = try await Self.runs(.open, nil)
        let distinct = Self.report("default sampling", .open, runs)
        #expect(Set(runs.map(\.assetIDs)).count == 1, "All runs must come from the same model assets")
        #expect(distinct > 1, "The control must show variation")
    }

    @Test(
        "Greedy sampling gives the same answer every time",
        .enabled(if: Live.isEnabled, "Live test: needs ASSAY_LIVE=1 and Apple Intelligence"),
        arguments: Prompt.allCases
    )
    func greedyIsRepeatable(prompt: Prompt) async throws {
        let runs = try await Self.runs(prompt, .greedy)
        let distinct = Self.report("greedy", prompt, runs)
        #expect(Set(runs.map(\.assetIDs)).count == 1, "All runs must come from the same model assets")
        #expect(distinct == 1)
    }

    @Test(
        "Random sampling with a fixed seed gives the same answer every time",
        .enabled(if: Live.isEnabled, "Live test: needs ASSAY_LIVE=1 and Apple Intelligence"),
        arguments: Prompt.allCases
    )
    func seededSamplingIsRepeatable(prompt: Prompt) async throws {
        let runs = try await Self.runs(prompt, .random(top: Self.top, seed: Self.seed))
        let distinct = Self.report("random(top: \(Self.top), seed: \(Self.seed))", prompt, runs)
        #expect(Set(runs.map(\.assetIDs)).count == 1, "All runs must come from the same model assets")
        #expect(distinct == 1)
    }

    /// The seed's own control: if two seeds gave the same answer, "repeatable with a fixed
    /// seed" could just mean the seed is ignored.
    @Test(
        "Different seeds give different answers on an open prompt",
        .enabled(if: Live.isEnabled, "Live test: needs ASSAY_LIVE=1 and Apple Intelligence")
    )
    func differentSeedsDiffer() async throws {
        let first = try await Live.respond(to: Prompt.open.text, options: Self.options(.random(top: Self.top, seed: 42)))
        let second = try await Live.respond(to: Prompt.open.text, options: Self.options(.random(top: Self.top, seed: 43)))
        #expect(first.output != second.output)
    }
}

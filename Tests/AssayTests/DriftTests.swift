// Drift's unit tests. "The model changed" is simulated by recording the same requests
// from two FakeModels that answer differently, so everything runs offline.

import Foundation
import FoundationModels
import Testing
@testable import Assay

@Suite("Drift")
struct DriftTests {

    final class Scratch {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("assay-drift-tests-\(UUID().uuidString)")

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        /// Records `answers` for `prompts`, in order, into a tape of its own directory.
        func record(_ generation: String, prompts: [String], answers: [String]) async throws -> URL {
            let cassette = try Cassette(
                "tape", mode: .record, recording: FakeModel(answers.map { .text($0) }),
                directory: directory.appendingPathComponent(generation),
                normalize: nil, redact: nil, filePath: #filePath, environment: [:]
            )
            for prompt in prompts {
                _ = try await LanguageModelSession(model: cassette.model).respond(to: prompt)
            }
            return cassette.url
        }
    }

    static let prompts = ["Capital of France?", "Capital of Italy?", "Capital of Spain?", "Capital of Peru?"]

    /// Passes when the answer names the right capital.
    static let namesTheCapital: Drift.Check = { request, answer in
        let capitals = ["France": "Paris", "Italy": "Rome", "Spain": "Madrid", "Peru": "Lima"]
        return capitals.contains { request.prompt.contains($0.key) && answer.contains($0.value) }
    }

    @Test("Each case is classified against the pass criterion")
    func classification() async throws {
        let scratch = Scratch()
        let old = try await scratch.record("old", prompts: Self.prompts, answers: ["Paris.", "Rome.", "Madrid.", "Bogotá."])
        let new = try await scratch.record("new", prompts: Self.prompts, answers: ["Paris.", "It's Rome.", "Barcelona.", "Lima."])

        let report = try Drift.compare(baseline: old, candidate: new, passes: Self.namesTheCapital)

        #expect(report.cases.map(\.kind) == [.unchanged, .changed, .flippedToFail, .flippedToPass])
        #expect(report.summary == "1 unchanged, 1 changed, 1 flipped to fail, 1 flipped to pass")
        #expect(report.count(.flippedToFail) == 1)
        #expect(report.cases[2].before == "Madrid.")
        #expect(report.cases[2].after == "Barcelona.")
    }

    @Test("An answer that failed before and still fails is its own kind")
    func stillFailing() async throws {
        let scratch = Scratch()
        let old = try await scratch.record("old", prompts: ["Capital of Peru?"], answers: ["Bogotá."])
        let new = try await scratch.record("new", prompts: ["Capital of Peru?"], answers: ["Quito."])
        let report = try Drift.compare(baseline: old, candidate: new, passes: Self.namesTheCapital)
        #expect(report.cases.map(\.kind) == [.stillFailing])
    }

    @Test("Without a pass criterion, cases are only unchanged or changed")
    func withoutChecks() async throws {
        let scratch = Scratch()
        let old = try await scratch.record("old", prompts: Self.prompts, answers: ["Paris.", "Rome.", "Madrid.", "Bogotá."])
        let new = try await scratch.record("new", prompts: Self.prompts, answers: ["Paris.", "It's Rome.", "Barcelona.", "Lima."])
        let report = try Drift.compare(baseline: old, candidate: new)
        #expect(report.cases.map(\.kind) == [.unchanged, .changed, .changed, .changed])
        #expect(!report.hasChecks)
    }

    @Test("Requests on only one side are added or removed")
    func addedAndRemoved() async throws {
        let scratch = Scratch()
        let old = try await scratch.record("old", prompts: ["a", "b"], answers: ["1", "2"])
        let new = try await scratch.record("new", prompts: ["b", "c"], answers: ["2", "3"])
        let report = try Drift.compare(baseline: old, candidate: new)
        #expect(report.cases.map(\.kind) == [.removed, .unchanged, .added])
        #expect(report.cases.map(\.request.prompt) == ["a", "b", "c"])
    }

    @Test("The same request recorded twice is compared recording by recording")
    func repeatedRequests() async throws {
        let scratch = Scratch()
        let old = try await scratch.record("old", prompts: ["flip", "flip"], answers: ["heads", "tails"])
        let new = try await scratch.record("new", prompts: ["flip", "flip"], answers: ["heads", "edge"])
        let report = try Drift.compare(baseline: old, candidate: new)
        #expect(report.cases.map(\.kind) == [.unchanged, .changed])
    }

    // MARK: Asking a model again

    @Test("check sends the tape's requests to a model again, with their instructions and history")
    func checkAsksAgain() async throws {
        let scratch = Scratch()
        let directory = scratch.directory.appendingPathComponent("conversation")
        do {
            let cassette = try Cassette(
                "tape", mode: .record, recording: FakeModel("Paris.", "Rome."), directory: directory,
                normalize: nil, redact: nil, filePath: #filePath, environment: [:]
            )
            let session = LanguageModelSession(model: cassette.model, instructions: "Be brief.")
            _ = try await session.respond(to: "Capital of France?", options: GenerationOptions(maximumResponseTokens: 30))
            _ = try await session.respond(to: "And of Italy?", options: GenerationOptions(maximumResponseTokens: 30))
        }
        let tape = directory.appendingPathComponent("tape.json")
        let before = try Data(contentsOf: tape)

        let newer = FakeModel("Paris.", "Roma!")
        let report = try await Drift.check(tape: tape, on: newer)

        #expect(report.cases.map(\.kind) == [.unchanged, .changed])
        // The model was asked the same things: instructions, the earlier turn as recorded, options.
        #expect(newer.calls.map(\.prompt) == ["Capital of France?", "And of Italy?"])
        #expect(newer.calls[1].transcript.count == 4)
        #expect(newer.calls[1].options.maximumResponseTokens == 30)
        #expect(newer.calls[1].options.samplingMode == .greedy)
        // Without `update`, the tape is left alone.
        #expect(try Data(contentsOf: tape) == before)
    }

    @Test("check with update replaces the tape with the new answers")
    func checkUpdates() async throws {
        let scratch = Scratch()
        let tape = try await scratch.record("old", prompts: ["Capital of Italy?"], answers: ["Rome."])
        _ = try await Drift.check(tape: tape, on: FakeModel("Roma!"), update: true)
        #expect(try Tape.read(from: tape).interactions.map(\.response.text) == ["Roma!"])
        // Both sides came from models that report no assets, so nothing counts as a new model.
        #expect(!FileManager.default.fileExists(atPath: tape.deletingLastPathComponent().appendingPathComponent("generations").path))
    }

    @Test("A structured request is asked again with its schema")
    func structuredRequest() async throws {
        let scratch = Scratch()
        let directory = scratch.directory.appendingPathComponent("structured")
        let json = #"{"name": "Paris", "population": 2100000}"#
        do {
            let cassette = try Cassette(
                "tape", mode: .record, recording: FakeModel(.json(json)), directory: directory,
                normalize: nil, redact: nil, filePath: #filePath, environment: [:]
            )
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "Describe Paris.", generating: CassetteTests.City.self)
        }
        let newer = FakeModel(.json(#"{"population": 2100000, "name": "Paris"}"#))
        let report = try await Drift.check(tape: directory.appendingPathComponent("tape.json"), on: newer)
        // Same content, keys in another order: not a change.
        #expect(report.cases.map(\.kind) == [.unchanged])
        #expect(newer.calls[0].expectsStructuredOutput)
    }

    // MARK: Generations

    static func tape(system: String, assets: [String], answer: String) -> Tape {
        let request = try! JSONDecoder().decode(
            Cassette.Request.self, from: Data(#"{"history": [], "prompt": "hi", "options": {}}"#.utf8)
        )
        return Tape(interactions: [Tape.Interaction(
            key: try! Canonical.key(for: request),
            request: request,
            response: Tape.Response(text: answer, outputTokens: 3),
            provenance: Tape.Provenance(
                recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
                systemVersion: system, assetIDs: assets, sampling: .greedy, seconds: 0.5
            )
        )])
    }

    @Test("A tape from another model is kept as an older generation")
    func archiveOnModelChange() throws {
        let scratch = Scratch()
        let url = scratch.directory.appendingPathComponent("tape.json")
        let old = Self.tape(system: "Version 27.2 (Build 26B123)", assets: ["model-1"], answer: "old")

        // The same model: nothing to keep.
        #expect(try old.archive(besides: url, ifModelDiffersFrom: ["model-1"]) == nil)

        // Another model: the old tape goes under generations/<name>/.
        let archived = try #require(try old.archive(besides: url, ifModelDiffersFrom: ["model-2"]))
        #expect(archived.path.hasSuffix("/generations/tape/\(old.generationLabel).json"))
        #expect(old.generationLabel.hasPrefix("27.2-26B123-"))
        #expect(try Tape.read(from: archived).interactions[0].response.text == "old")
    }

    @Test("The report says whether the model assets differ")
    func modelChangedFlag() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(at: scratch.directory, withIntermediateDirectories: true)
        let a = scratch.directory.appendingPathComponent("a.json"), b = scratch.directory.appendingPathComponent("b.json"), c = scratch.directory.appendingPathComponent("c.json")
        try Self.tape(system: "Version 27.2 (Build 26B123)", assets: ["model-1"], answer: "x").write(to: a)
        try Self.tape(system: "Version 27.3 (Build 26C200)", assets: ["model-2"], answer: "y").write(to: b)
        try Self.tape(system: "Version 27.3 (Build 26C200)", assets: ["model-1"], answer: "x").write(to: c)

        let changed = try Drift.compare(baseline: a, candidate: b)
        #expect(changed.modelChanged)
        #expect(changed.cases[0].secondsBefore == 0.5)

        // A new OS build with the same model assets is not a new model.
        #expect(!(try Drift.compare(baseline: a, candidate: c)).modelChanged)

        // Tapes directly in the directory are listed; generations/ is not descended into.
        try Self.tape(system: "Version 27.0 (Build 26A1)", assets: ["model-0"], answer: "w")
            .archive(besides: a, ifModelDiffersFrom: ["model-1"])
        #expect(try Drift.tapes(in: scratch.directory).map(\.lastPathComponent) == ["a.json", "b.json", "c.json"])
    }

    // MARK: The report

    @Test("The Markdown report has the counts and the before and after of what changed")
    func markdown() async throws {
        let scratch = Scratch()
        let old = try await scratch.record("old", prompts: Self.prompts, answers: ["Paris.", "Rome.", "Madrid.", "Bogotá."])
        let new = try await scratch.record("new", prompts: Self.prompts, answers: ["Paris.", "It's Rome.", "Barcelona.", "Lima."])
        let report = try Drift.compare(baseline: old, candidate: new, passes: Self.namesTheCapital)
        let markdown = report.markdown()

        #expect(markdown.contains("**4 cases: 1 unchanged, 1 changed, 1 flipped to fail, 1 flipped to pass.**"))
        #expect(markdown.contains("| Flipped to fail | 1 |"))
        #expect(markdown.contains("## Flipped to fail (1)"))
        #expect(markdown.contains("### `tape`: Capital of Spain?"))
        #expect(markdown.contains("> Madrid."))
        #expect(markdown.contains("> Barcelona."))
        // Unchanged cases aren't listed one by one.
        #expect(!markdown.contains("Capital of France?"))
        // Failures come before changes that still pass.
        let fail = try #require(markdown.range(of: "## Flipped to fail"))
        let change = try #require(markdown.range(of: "## Changed"))
        #expect(fail.lowerBound < change.lowerBound)
    }

    @Test("Reports of several tapes merge into one")
    func merged() async throws {
        let scratch = Scratch()
        let a = try await scratch.record("a", prompts: ["x"], answers: ["1"])
        let b = try await scratch.record("b", prompts: ["x"], answers: ["2"])
        let merged = DriftReport.merged([
            try Drift.compare(baseline: a, candidate: a),
            try Drift.compare(baseline: a, candidate: b),
        ])
        #expect(merged.summary == "1 unchanged, 1 changed")
    }
}

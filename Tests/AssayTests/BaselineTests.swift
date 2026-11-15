// Baselines: a manual drift ledger, until cassettes (M2) exist.
//
// A device holds one version of the model. After an OS or model update the old one is
// gone, and so is the way it answered, unless it was recorded first. `recordBaseline`
// writes what the current model answers to a fixed set of prompts, with greedy sampling,
// into `Baselines/`, one file per model version. `compareLatestBaselines` reports what
// changed between the two most recent files.
//
//   scripts/test.sh record     before and after every OS update
//   scripts/test.sh compare    after the second recording
//
// This is a stopgap, not the cassette design: one hard-coded prompt set, no request
// matching, no replay.

import Foundation
import FoundationModels
import Testing

@Suite("Baselines: what the current model answers", .serialized)
struct BaselineTests {

    struct Case: Sendable {
        var id: String
        var prompt: String
        var structured = false
    }

    /// Fixed on purpose: a baseline is only comparable with another one recorded from the
    /// same prompts. Add cases at the end; don't edit or reorder existing ones.
    static let cases: [Case] = [
        Case(id: "capital", prompt: "What is the capital of France? Answer in one word."),
        Case(id: "sum", prompt: "What is 17 + 26? Answer with the number only."),
        Case(id: "forest", prompt: "Write a short paragraph, about 60 words, describing a walk through a forest in autumn."),
        Case(id: "summarize", prompt: "Summarize in one sentence: The meeting moved from Tuesday to Thursday because the client is travelling, and the agenda now includes the budget review."),
        Case(id: "sentiment", prompt: "Classify the sentiment of this review as positive, negative or neutral. Answer with one word. Review: The battery lasts all day but the screen scratches easily."),
        Case(id: "formal", prompt: "Rewrite this sentence to sound more formal: hey, can u send me the report asap?"),
        Case(id: "steps", prompt: "List three steps to cook pasta. One short line per step."),
        Case(id: "trail", prompt: "Describe a hiking trail in a pine forest.", structured: true),
    ]

    struct Baseline: Codable {
        var formatVersion = 1
        var recordedAt: String
        var systemVersion: String
        var assetIDs: [String]
        var sampling = "greedy"
        var maximumResponseTokens: Int
        var answers: [Answer]
    }

    struct Answer: Codable {
        var id: String
        var prompt: String
        var structured: Bool
        var output: String
        var outputTokens: Int
        /// False when two consecutive greedy runs disagreed. Such a case can't be used to
        /// tell a model change from noise.
        var repeatable: Bool
    }

    /// `<repo>/Baselines`, found from this file's path (Tests/AssayTests/BaselineTests.swift).
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Baselines", isDirectory: true)

    /// "Version 27.2 (Build 26B123)" + the main model asset → "macOS-27.2-26B123_model-16.1000.0.13.103404".
    static func fileStem(systemVersion: String, assetIDs: [String]) -> String {
        let system = systemVersion
            .replacingOccurrences(of: "Version ", with: "")
            .replacingOccurrences(of: " (Build ", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ", with: "_")
        let mainAsset = assetIDs.first { !$0.contains("tokenizer") && !$0.contains("draft") } ?? assetIDs.joined()
        var model = "unknown"
        if let match = mainAsset.firstMatch(of: /variant=\D*([\d.]+\d)/) {
            model = String(match.1)
        }
        return "macOS-\(system)_model-\(model)"
    }

    static func loadAll() throws -> [(url: URL, baseline: Baseline)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return try urls
            .filter { $0.pathExtension == "json" }
            .map { (url: $0, baseline: try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: $0))) }
            .sorted { $0.baseline.recordedAt < $1.baseline.recordedAt }
    }

    @Test(
        "Record what the current model answers",
        .enabled(if: Live.flag("ASSAY_RECORD") && Live.modelIsAvailable, "Recording: needs ASSAY_RECORD=1 and Apple Intelligence")
    )
    func recordBaseline() async throws {
        let options = Live.greedy()
        var answers: [Answer] = []
        var systemVersion: String?
        var assetSets: Set<[String]> = []

        for testCase in Self.cases {
            let first = try await Live.respond(to: testCase.prompt, structured: testCase.structured, options: options)
            let second = try await Live.respond(to: testCase.prompt, structured: testCase.structured, options: options)
            assetSets.insert(first.assetIDs)
            assetSets.insert(second.assetIDs)
            systemVersion = first.systemVersion ?? systemVersion
            answers.append(Answer(
                id: testCase.id,
                prompt: testCase.prompt,
                structured: testCase.structured,
                output: first.output,
                outputTokens: first.outputTokens,
                repeatable: first.output == second.output
            ))
        }

        // One recording must come from one model.
        try #require(assetSets.count == 1, "The model assets changed while recording")
        let assetIDs = try #require(assetSets.first)
        let system = try #require(systemVersion, "The response carried no systemVersion")

        let baseline = Baseline(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            systemVersion: system,
            assetIDs: assetIDs,
            maximumResponseTokens: options.maximumResponseTokens ?? 0,
            answers: answers
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let url = Self.directory.appendingPathComponent(Self.fileStem(systemVersion: system, assetIDs: assetIDs) + ".json")
        try encoder.encode(baseline).write(to: url, options: .atomic)

        let unstable = answers.filter { !$0.repeatable }.map(\.id)
        print("[Baseline] recorded \(answers.count) answers to \(url.lastPathComponent)")
        print("[Baseline] system: \(system)")
        print("[Baseline] not repeatable: \(unstable.isEmpty ? "none" : unstable.joined(separator: ", "))")
    }

    @Test(
        "Compare the two most recent baselines",
        .enabled(if: Live.flag("ASSAY_COMPARE"), "Comparison: needs ASSAY_COMPARE=1")
    )
    func compareLatestBaselines() throws {
        let all = try Self.loadAll()
        guard all.count >= 2 else {
            print("[Baseline] \(all.count) baseline(s) in Baselines/: nothing to compare yet")
            return
        }
        let (old, new) = (all[all.count - 2], all[all.count - 1])
        print("[Baseline] old: \(old.url.lastPathComponent)")
        print("[Baseline] new: \(new.url.lastPathComponent)")
        print("[Baseline] same model assets: \(old.baseline.assetIDs == new.baseline.assetIDs)")

        var unchanged = 0
        var changed: [String] = []
        for answer in new.baseline.answers {
            guard let before = old.baseline.answers.first(where: { $0.id == answer.id }) else {
                print("[Baseline] \(answer.id): new case, no earlier answer")
                continue
            }
            if before.prompt != answer.prompt {
                print("[Baseline] \(answer.id): the prompt changed, not comparable")
            } else if before.output == answer.output {
                unchanged += 1
            } else {
                changed.append(answer.id)
                let note = before.repeatable && answer.repeatable ? "" : " (not repeatable: may be noise)"
                print("[Baseline] \(answer.id): CHANGED\(note)")
                print("[Baseline]   before: \(before.output)")
                print("[Baseline]   after:  \(answer.output)")
            }
        }
        print("[Baseline] \(unchanged) unchanged, \(changed.count) changed")
    }
}

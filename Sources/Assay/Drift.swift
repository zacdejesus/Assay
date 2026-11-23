// Drift: what changed between two recordings of the same requests.
// Design: docs/decisions/0006-drift.md

import Foundation
import FoundationModels

/// Compares what a model answered when a tape was recorded with what a model answers now.
///
/// Only one version of the on-device model exists on a device at a time. What the previous
/// one answered survives only in a tape, so a tape is what a new model gets compared with.
///
/// ```swift
/// let report = try await Drift.check(tape: cassette.url) { request, answer in
///     answer.contains("Paris")
/// }
/// #expect(report.count(.flippedToFail) == 0, "\(report.markdown())")
/// ```
public enum Drift {

    /// Decides whether an answer is acceptable. It receives the request and the answer as
    /// text; a structured answer arrives as JSON.
    public typealias Check = @Sendable (_ request: Cassette.Request, _ answer: String) -> Bool

    /// Sends every request in a tape to `model` again and compares the answers.
    ///
    /// - Parameters:
    ///   - tape: A tape file.
    ///   - model: The model to ask. The on-device model by default.
    ///   - passes: The pass criterion. Without it, cases are only unchanged or changed.
    ///   - update: Whether to replace the tape with the new answers. If the model changed,
    ///     the old tape is kept under `generations/`.
    public static func check<Model: LanguageModel>(
        tape url: URL,
        on model: Model = SystemLanguageModel.default,
        passes: Check? = nil,
        update: Bool = false
    ) async throws -> DriftReport {
        let baseline = try Tape.read(from: url)
        let recorder = Cassette.Recorder(model)

        var candidate = Tape(machine: Tape.currentMachine)
        // One at a time, in recorded order: the model is shared, and running requests in
        // parallel would add a variable the comparison doesn't control.
        for interaction in baseline.interactions {
            let (response, provenance) = try await recorder.perform(
                try Cassette.LiveCall(interaction.request), redact: nil
            )
            candidate.interactions.append(Tape.Interaction(
                key: interaction.key, request: interaction.request, response: response, provenance: provenance
            ))
        }

        if update, let first = candidate.interactions.first {
            try baseline.archive(besides: url, ifModelDiffersFrom: first.provenance.assetIDs)
            try candidate.write(to: url)
        }
        return DriftReport(tape: name(of: url), baseline: baseline, candidate: candidate, passes: passes)
    }

    /// Compares two tape files without calling any model: an older generation with the
    /// current tape, for example.
    public static func compare(baseline: URL, candidate: URL, passes: Check? = nil) throws -> DriftReport {
        DriftReport(
            tape: name(of: candidate),
            baseline: try Tape.read(from: baseline),
            candidate: try Tape.read(from: candidate),
            passes: passes
        )
    }

    /// The tape files directly inside a directory, sorted by name. Older generations live
    /// in a subdirectory and aren't included.
    public static func tapes(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func name(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// The result of a comparison: one case per recorded request.
public struct DriftReport: Sendable {

    public enum Kind: String, Sendable, CaseIterable {
        /// The same answer.
        case unchanged
        /// A different answer that still passes, or a different answer when there is no
        /// pass criterion. Information, not a failure.
        case changed
        /// It passed before and fails now.
        case flippedToFail
        /// It failed before and passes now.
        case flippedToPass
        /// It failed before and fails now, whether or not the answer changed.
        case stillFailing
        /// A different answer to a request recorded with random sampling and no seed, which
        /// still passes or has no pass criterion. The same model can answer it differently,
        /// so the difference says nothing about the model. Not a failure.
        case sampled
        /// A request the baseline doesn't have.
        case added
        /// A request the candidate doesn't have.
        case removed

        var title: String {
            switch self {
            case .unchanged: "Unchanged"
            case .changed: "Changed"
            case .flippedToFail: "Flipped to fail"
            case .flippedToPass: "Flipped to pass"
            case .stillFailing: "Still failing"
            case .sampled: "Changed, randomly sampled"
            case .added: "Added"
            case .removed: "Removed"
            }
        }
    }

    public struct Case: Sendable {
        public var tape: String
        public var request: Cassette.Request
        public var kind: Kind
        /// The baseline's answer; `nil` for an added request.
        public var before: String?
        /// The candidate's answer; `nil` for a removed request.
        public var after: String?
        public var tokensBefore: Int?
        public var tokensAfter: Int?
        public var secondsBefore: Double?
        public var secondsAfter: Double?
    }

    /// A model, as a tape identifies it.
    public struct Generation: Sendable, Hashable {
        public var systemVersion: String?
        public var assetIDs: [String]
    }

    public var cases: [Case]
    /// The models behind the baseline's answers. Normally one.
    public var baseline: [Generation]
    /// The models behind the candidate's answers.
    public var candidate: [Generation]
    /// Whether a pass criterion was used.
    public var hasChecks: Bool

    /// Whether the two sides came from different model assets. If the answers changed and
    /// this is false, the change didn't come from a new model.
    public var modelChanged: Bool {
        Set(baseline.map(\.assetIDs)) != Set(candidate.map(\.assetIDs))
    }

    public func count(_ kind: Kind) -> Int {
        cases.count { $0.kind == kind }
    }

    /// Cases that call for a look: everything but unchanged and randomly sampled changes.
    /// What `assay drift --fail-on-change` fails on.
    public var changeCount: Int {
        cases.count { $0.kind != .unchanged && $0.kind != .sampled }
    }

    /// Cases whose request was recorded with random sampling and no seed.
    public var randomlySampledCount: Int {
        cases.count { $0.request.options.isRandomlySampled }
    }

    /// "37 unchanged, 3 flipped to fail, 1 flipped to pass". Counts, not percentages: a
    /// percentage of a small suite looks like more evidence than it is.
    public var summary: String {
        let parts = Kind.allCases.compactMap { kind -> String? in
            let count = count(kind)
            return count == 0 ? nil : "\(count) \(kind.title.lowercased())"
        }
        return parts.isEmpty ? "no cases" : parts.joined(separator: ", ")
    }

    /// Joins the reports of several tapes into one.
    public static func merged(_ reports: [DriftReport]) -> DriftReport {
        func distinct(_ generations: [Generation]) -> [Generation] {
            var seen: Set<Generation> = []
            return generations.filter { seen.insert($0).inserted }
        }
        return DriftReport(
            cases: reports.flatMap(\.cases),
            baseline: distinct(reports.flatMap(\.baseline)),
            candidate: distinct(reports.flatMap(\.candidate)),
            hasChecks: reports.contains { $0.hasChecks }
        )
    }

    init(cases: [Case], baseline: [Generation], candidate: [Generation], hasChecks: Bool) {
        self.cases = cases
        self.baseline = baseline
        self.candidate = candidate
        self.hasChecks = hasChecks
    }

    init(tape: String, baseline: Tape, candidate: Tape, passes: Drift.Check?) {
        // The same request can be recorded more than once; the nth recording on one side
        // is compared with the nth on the other. `unmatched` holds the candidate's
        // interactions that haven't been paired yet, in recorded order.
        var unmatched = Array(candidate.interactions.indices)

        var cases: [Case] = []
        for old in baseline.interactions {
            let before = (try? old.response.emitted) ?? ""
            guard let position = unmatched.firstIndex(where: { candidate.interactions[$0].key == old.key }) else {
                cases.append(Case(
                    tape: tape, request: old.request, kind: .removed, before: before, after: nil,
                    tokensBefore: old.response.outputTokens, secondsBefore: old.provenance.seconds
                ))
                continue
            }
            let new = candidate.interactions[unmatched.remove(at: position)]
            let after = (try? new.response.emitted) ?? ""

            // A different answer that would be "changed" is "sampled" when the same model could
            // have given it. Flips stay flips: the outcome matters even if sampling caused it.
            let changed: Kind = old.request.options.isRandomlySampled ? .sampled : .changed
            let kind: Kind
            if let passes {
                switch (passes(old.request, before), passes(new.request, after)) {
                case (true, true): kind = before == after ? .unchanged : changed
                case (true, false): kind = .flippedToFail
                case (false, true): kind = .flippedToPass
                case (false, false): kind = .stillFailing
                }
            } else {
                kind = before == after ? .unchanged : changed
            }
            cases.append(Case(
                tape: tape, request: old.request, kind: kind, before: before, after: after,
                tokensBefore: old.response.outputTokens, tokensAfter: new.response.outputTokens,
                secondsBefore: old.provenance.seconds, secondsAfter: new.provenance.seconds
            ))
        }
        // Whatever is left on the candidate's side has no counterpart.
        for index in unmatched {
            let new = candidate.interactions[index]
            cases.append(Case(
                tape: tape, request: new.request, kind: .added, before: nil, after: (try? new.response.emitted) ?? "",
                tokensAfter: new.response.outputTokens, secondsAfter: new.provenance.seconds
            ))
        }

        func generations(_ tape: Tape) -> [Generation] {
            var seen: Set<Generation> = []
            return tape.interactions
                .map { Generation(systemVersion: $0.provenance.systemVersion, assetIDs: $0.provenance.assetIDs) }
                .filter { seen.insert($0).inserted }
        }
        self.init(cases: cases, baseline: generations(baseline), candidate: generations(candidate), hasChecks: passes != nil)
    }
}

// MARK: - Markdown

extension DriftReport {

    /// The report as Markdown: what was compared, the counts, and the before and after of
    /// every case that isn't unchanged.
    public func markdown() -> String {
        var lines = ["# Drift report", ""]
        lines.append("- **Baseline:** \(Self.describe(baseline))")
        lines.append("- **Candidate:** \(Self.describe(candidate))")
        lines.append("- **Model assets:** \(modelChanged ? "different" : "the same on both sides")")
        if !hasChecks {
            lines.append("- No pass criterion was given, so cases are only unchanged or changed.")
        }
        if randomlySampledCount > 0 {
            lines.append("- **Random sampling:** \(randomlySampledCount) of \(cases.count) cases were recorded with random "
                + "sampling and no seed. The same model can answer those differently, so their changes are listed "
                + "apart and don't count as changes. Record with greedy sampling (or a seed) to compare models.")
        }
        lines += ["", "**\(cases.count) cases: \(summary).**", ""]

        lines += ["| Result | Cases |", "|---|---|"]
        for kind in Kind.allCases where count(kind) > 0 {
            lines.append("| \(kind.title) | \(count(kind)) |")
        }

        let tokens = cases.compactMap { $0.tokensBefore != nil && $0.tokensAfter != nil ? ($0.tokensBefore!, $0.tokensAfter!) : nil }
        if !tokens.isEmpty {
            let before = tokens.reduce(0) { $0 + $1.0 }, after = tokens.reduce(0) { $0 + $1.1 }
            lines += ["", "Output tokens over the compared cases: \(before) → \(after)."]
        }
        let seconds = cases.compactMap { $0.secondsBefore != nil && $0.secondsAfter != nil ? ($0.secondsBefore!, $0.secondsAfter!) : nil }
        if !seconds.isEmpty {
            let before = seconds.reduce(0) { $0 + $1.0 }, after = seconds.reduce(0) { $0 + $1.1 }
            lines.append("Time to answer over the compared cases: \(Self.format(before)) s → \(Self.format(after)) s "
                + "(noisy: the first request of a run is much slower).")
        }

        // The cases that need a human, most important first.
        let order: [Kind] = [.flippedToFail, .flippedToPass, .stillFailing, .changed, .added, .removed, .sampled]
        for kind in order {
            let matching = cases.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }
            lines += ["", "## \(kind.title) (\(matching.count))"]
            for item in matching {
                lines += ["", "### `\(item.tape)`: \(Self.oneLine(item.request.prompt))", ""]
                if let instructions = item.request.instructions {
                    lines.append("Instructions: \(Self.oneLine(instructions))")
                    lines.append("")
                }
                if let before = item.before {
                    lines += ["Before:", "", Self.quote(before), ""]
                }
                if let after = item.after {
                    lines += ["After:", "", Self.quote(after), ""]
                }
                if let before = item.tokensBefore, let after = item.tokensAfter, before != after {
                    lines.append("Output tokens: \(before) → \(after)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func describe(_ generations: [Generation]) -> String {
        guard !generations.isEmpty else { return "nothing recorded" }
        return generations.map { generation in
            let system = generation.systemVersion ?? "unknown system"
            let assets = generation.assetIDs.isEmpty ? "no model assets reported" : generation.assetIDs.map { "`\($0)`" }.joined(separator: ", ")
            return "\(system); \(assets)"
        }.joined(separator: " / ")
    }

    private static func oneLine(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 100 ? flat.prefix(100) + "…" : flat
    }

    private static func quote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
    }

    private static func format(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

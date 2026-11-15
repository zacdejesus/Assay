// Shared by the suites that call the real on-device model.
// Live tests are opt-in: they need a machine with Apple Intelligence, they take seconds
// instead of milliseconds, and their results depend on the installed model.

import Foundation
import FoundationModels
import Testing

enum Live {

    static let modelIsAvailable = SystemLanguageModel.default.isAvailable

    /// `ASSAY_LIVE=1`: run the tests that call the real model.
    static let isEnabled = flag("ASSAY_LIVE") && modelIsAvailable

    static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment[name] == "1"
    }

    /// A small structured-output type, for the cases that use guided generation.
    @Generable
    struct Trail {
        var name: String
        var lengthInKilometers: Int
        var highlights: [String]
    }

    /// What one call to the model produced.
    struct Run: Sendable, Equatable {
        /// The response as canonical JSON text (keys sorted). Same representation for plain
        /// text and structured output, so one comparison works for both.
        /// Canonical because `GeneratedContent.jsonString` doesn't keep a stable key order:
        /// the same structured answer comes back with its keys in a different order from
        /// one response to the next (Experiment C).
        var output: String
        /// The model assets that produced this answer, sorted. The framework returns the
        /// same IDs in a different order from one response to the next (Experiment C), so
        /// the raw array can't be compared directly.
        var assetIDs: [String]
        /// e.g. "Version 27.2 (Build 26B123)".
        var systemVersion: String?
        var outputTokens: Int

        init<Content>(_ response: LanguageModelSession.Response<Content>) {
            var assetIDs: [String] = []
            var systemVersion: String?
            for entry in response.transcriptEntries {
                guard case .response(let recorded) = entry else { continue }
                assetIDs += recorded.assetIDs
                if let value = recorded.metadata["systemVersion"] {
                    systemVersion = (try? value.value(String.self)) ?? value.jsonString
                }
            }
            self.output = Live.canonicalJSON(response.rawContent.jsonString)
            self.assetIDs = assetIDs.sorted()
            self.systemVersion = systemVersion
            self.outputTokens = response.usage.output.totalTokenCount
        }
    }

    /// Re-serializes JSON with sorted keys. Returns the input unchanged if it isn't JSON.
    static func canonicalJSON(_ json: String) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]),
            let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
            )
        else { return json }
        return String(decoding: data, as: UTF8.self)
    }

    /// One call, in a new session.
    /// A new session each time: the transcript accumulates (Experiment A), so a reused
    /// session would send a different request on every call.
    static func respond(
        to prompt: String,
        structured: Bool = false,
        options: GenerationOptions
    ) async throws -> Run {
        let session = LanguageModelSession()
        if structured {
            return Run(try await session.respond(to: prompt, generating: Trail.self, options: options))
        } else {
            return Run(try await session.respond(to: prompt, options: options))
        }
    }

    /// Greedy sampling with a bounded response: the options a recording uses, so that it
    /// reflects the model and not sampling luck.
    static func greedy(maximumResponseTokens: Int = 160) -> GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maximumResponseTokens)
    }
}

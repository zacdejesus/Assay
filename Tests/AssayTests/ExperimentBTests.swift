// Experiment B (M0 spike): can a custom model wrap the real on-device model?
// Findings in docs/notes/foundationmodels.md: wrapping and forwarding work; reading the
// channel's events doesn't (they're opaque, and without a public `finish()` a reader in
// the middle can't know when the last event arrived). Recording goes through
// `session.transcript` instead, which this test also checks.
//
// Live test: it calls the real model, so it's opt-in. Run it with
//   ASSAY_LIVE=1 swift test --filter ExperimentB

import FoundationModels
import Testing

@Suite("Experiment B: wrapping the real model")
struct ExperimentBTests {

    /// A decorator model around `SystemLanguageModel`.
    struct WrappingModel: LanguageModel {
        typealias Executor = WrappingExecutor

        var base: SystemLanguageModel = .default

        /// Claims exactly what the real model claims.
        var capabilities: LanguageModelCapabilities { base.capabilities }

        /// Carries the real model's own configuration, so the wrapper can build its executor.
        var executorConfiguration: WrappingExecutor.Configuration {
            .init(base: base.executorConfiguration)
        }
    }

    struct WrappingExecutor: LanguageModelExecutor {
        typealias Model = WrappingModel

        struct Configuration: Hashable, Sendable {
            var base: SystemLanguageModel.Executor.Configuration
        }

        private let inner: SystemLanguageModel.Executor

        init(configuration: Configuration) {
            inner = SystemLanguageModel.Executor(configuration: configuration.base)
        }

        func prewarm(model: WrappingModel, transcript: Transcript) {
            inner.prewarm(model: model.base, transcript: transcript)
        }

        /// Passes the session's own channel straight through.
        nonisolated(nonsending) func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: WrappingModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            try await inner.respond(to: request, model: model.base, streamingInto: channel)
        }
    }

    @Test(
        "A wrapper forwards the real model, and the transcript records its provenance",
        .enabled(if: Live.isEnabled, "Live test: needs ASSAY_LIVE=1 and Apple Intelligence")
    )
    func wrapperForwardsRealModel() async throws {
        let session = LanguageModelSession(model: WrappingModel())
        let response = try await session.respond(to: "Reply with the single word: pong")
        #expect(!response.content.isEmpty)

        // Provenance through public API only: which model assets produced this answer?
        let entries = session.transcript.compactMap { entry -> Transcript.Response? in
            if case .response(let response) = entry { return response }
            return nil
        }
        let recorded = try #require(entries.last)
        #expect(!recorded.assetIDs.isEmpty)
        #expect(recorded.metadata["systemVersion"] != nil)
    }
}

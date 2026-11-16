import FoundationModels
import Observation

/// The app's logic: decides which screen to show and measures one response.
///
/// It has two inputs it doesn't own, and both are plain closures written with Apple's
/// types. The app uses the defaults; a test passes its own.
@MainActor
@Observable
public final class SpeedTest {

    public enum Screen: Equatable {
        /// The model can't be used. The app shows why instead of the test.
        case unavailable(SystemLanguageModel.Availability.UnavailableReason)
        case ready
        case running
        case finished
        /// The request failed. The text is what the user reads.
        case failed(String)
    }

    public private(set) var screen: Screen
    public private(set) var meter = SpeedMeter()
    /// The response so far.
    public private(set) var text = ""
    /// The model assets that produced the latest response. Empty until one arrives, and for
    /// models that don't report any.
    public private(set) var modelAssets: [String] = []
    public var prompt = "Write a short story about a lighthouse keeper who finds a message in a bottle."

    @ObservationIgnored private let availability: () -> SystemLanguageModel.Availability
    @ObservationIgnored private let makeSession: () -> LanguageModelSession

    /// - Parameters:
    ///   - availability: Whether the model can be used right now.
    ///   - makeSession: A new session for each run, so every run sends the same request.
    public init(
        availability: @escaping () -> SystemLanguageModel.Availability = {
            SystemLanguageModel.default.availability
        },
        makeSession: @escaping () -> LanguageModelSession = { LanguageModelSession() }
    ) {
        self.availability = availability
        self.makeSession = makeSession
        self.screen = Self.screen(for: availability())
    }

    /// Reads availability again. Called when the user taps "Check again" and when the app
    /// comes back to the foreground: a model that was downloading may be ready now.
    /// A run in progress is left alone.
    public func refreshAvailability() {
        guard screen != .running else { return }
        switch availability() {
        case .available:
            if case .unavailable = screen { screen = .ready }
        case .unavailable(let reason):
            screen = .unavailable(reason)
        }
    }

    /// Sends the prompt and measures the response as it streams.
    public func run() async {
        refreshAvailability()
        if case .unavailable = screen { return }
        guard screen != .running else { return }

        screen = .running
        meter = SpeedMeter()
        text = ""

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let options = GenerationOptions(maximumResponseTokens: 400)
            let stream = makeSession().streamResponse(to: prompt, options: options)
            for try await snapshot in stream {
                text = snapshot.content
                let assets = ModelAssets.identifiers(in: snapshot.transcriptEntries)
                if !assets.isEmpty { modelAssets = assets }
                meter.record(
                    tokenCount: snapshot.usage.output.totalTokenCount,
                    elapsed: clock.now - start
                )
            }
            screen = .finished
        } catch {
            screen = .failed(Self.message(for: error))
        }
    }

    /// What the user reads when a run fails. Apple's safety filter is the failure a user is
    /// most likely to cause, so it says what to do about it. It can fire on the prompt or
    /// partway through the answer.
    static func message(for error: any Error) -> String {
        switch error {
        case LanguageModelError.guardrailViolation:
            "Apple's safety filter stopped this response. Try a different prompt."
        case LanguageModelError.refusal:
            "The model declined to answer. Try a different prompt."
        default:
            error.localizedDescription
        }
    }

    private static func screen(for availability: SystemLanguageModel.Availability) -> Screen {
        switch availability {
        case .available: .ready
        case .unavailable(let reason): .unavailable(reason)
        }
    }
}

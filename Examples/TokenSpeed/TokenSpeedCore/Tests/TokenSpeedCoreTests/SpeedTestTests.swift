// The app's tests. They use Assay's FakeModel and AvailabilityScript; the app target doesn't.
// They run offline, without Apple Intelligence, in milliseconds.

import Assay
import Foundation
import FoundationModels
import Testing
import TokenSpeedCore

@MainActor
@Suite("SpeedTest")
struct SpeedTestTests {

    struct Offline: Error, LocalizedError {
        var errorDescription: String? { "The model is offline." }
    }

    static func speedTest(
        _ script: AvailabilityScript = AvailabilityScript(.available),
        model: FakeModel
    ) -> SpeedTest {
        SpeedTest(availability: script.next, makeSession: { LanguageModelSession(model: model) })
    }

    // MARK: Fallback

    @Test(
        "The fallback screen appears for every reason the model can be unavailable",
        arguments: [
            SystemLanguageModel.Availability.UnavailableReason.deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
        ]
    )
    func fallbackAppears(reason: SystemLanguageModel.Availability.UnavailableReason) {
        let test = Self.speedTest(AvailabilityScript(.unavailable(reason)), model: FakeModel("unused"))
        #expect(test.screen == .unavailable(reason))
    }

    @Test("Each reason has its own message, and only an ineligible device can't retry")
    func fallbackMessages() {
        let reasons: [SystemLanguageModel.Availability.UnavailableReason] = [
            .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
        ]
        let fallbacks = reasons.map(Fallback.init)
        #expect(Set(fallbacks.map(\.title)).count == 3)
        #expect(fallbacks.map(\.canRetry) == [false, true, true])
    }

    @Test("The model is never called while it is unavailable")
    func unavailableModelIsNotCalled() async {
        let model = FakeModel("unused")
        let test = Self.speedTest(AvailabilityScript(.unavailable(.deviceNotEligible)), model: model)
        await test.run()
        #expect(model.calls.isEmpty)
        #expect(test.screen == .unavailable(.deviceNotEligible))
    }

    @Test("Checking again moves from 'getting ready' to the test once the model is available")
    func modelBecomesAvailable() {
        let script = AvailabilityScript(.unavailable(.modelNotReady), .unavailable(.modelNotReady), .available)
        let test = Self.speedTest(script, model: FakeModel("unused"))
        #expect(test.screen == .unavailable(.modelNotReady))
        test.refreshAvailability()
        #expect(test.screen == .unavailable(.modelNotReady))
        test.refreshAvailability()
        #expect(test.screen == .ready)
        #expect(script.isFinished)
    }

    @Test("The model going away after a run brings the fallback back")
    func modelBecomesUnavailable() async {
        let script = AvailabilityScript(.available, .available, .unavailable(.appleIntelligenceNotEnabled))
        let test = Self.speedTest(script, model: FakeModel("Done."))
        await test.run()
        #expect(test.screen == .finished)
        test.refreshAvailability()
        #expect(test.screen == .unavailable(.appleIntelligenceNotEnabled))
    }

    // MARK: Measuring

    @Test("A run shows the response and counts its tokens")
    func runMeasuresTheResponse() async {
        let model = FakeModel(.chunks(["The ", "keeper ", "waved."]))
        let test = Self.speedTest(model: model)
        #expect(test.screen == .ready)
        test.prompt = "Tell me a story."

        await test.run()

        #expect(test.screen == .finished)
        #expect(test.text == "The keeper waved.")
        #expect(test.meter.tokenCount == 3)   // FakeModel reports one token per chunk
        #expect(test.meter.timeToFirstToken != nil)
        #expect((test.meter.tokensPerSecond ?? 0) > 0)
        #expect(model.calls.map(\.prompt) == ["Tell me a story."])
    }

    @Test("A slow model shows up as time to first token")
    func slowModel() async throws {
        let model = FakeModel(.text("Late.").delayed(by: .milliseconds(100)))
        let test = Self.speedTest(model: model)
        await test.run()
        #expect(try #require(test.meter.timeToFirstToken) >= .milliseconds(100))
    }

    @Test("Each run starts from zero, in a new session")
    func secondRunStartsOver() async {
        let model = FakeModel(.chunks(["one ", "two ", "three"]), "four")
        let test = Self.speedTest(model: model)
        await test.run()
        await test.run()
        #expect(test.text == "four")
        #expect(test.meter.tokenCount == 1)
        // A reused session would have sent the first exchange again.
        #expect(model.calls.map(\.transcript.count) == [1, 1])
    }

    // MARK: Errors

    @Test("A failing model shows its error, and the next run recovers")
    func failureThenRecovery() async {
        let model = FakeModel(.failure(Offline()), "Back.")
        let test = Self.speedTest(model: model)

        await test.run()
        #expect(test.screen == .failed("The model is offline."))
        #expect(test.meter.tokensPerSecond == nil)

        await test.run()
        #expect(test.screen == .finished)
        #expect(test.text == "Back.")
    }

    @Test("Apple's safety filter is explained")
    func safetyFilter() async {
        let blocked = LanguageModelError.guardrailViolation(.init(debugDescription: "May contain unsafe content"))
        let model = FakeModel(.failure(blocked))
        let test = Self.speedTest(model: model)
        await test.run()
        #expect(test.screen == .failed("Apple's safety filter stopped this response. Try a different prompt."))
    }

    @Test("A refusal is explained too")
    func refusal() async {
        let refused = LanguageModelError.refusal(.init(explanation: "No.", debugDescription: "refused"))
        let test = Self.speedTest(model: FakeModel(.failure(refused)))
        await test.run()
        #expect(test.screen == .failed("The model declined to answer. Try a different prompt."))
    }
}

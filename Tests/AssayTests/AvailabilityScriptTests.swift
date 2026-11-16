import Assay
import FoundationModels
import Testing

@Suite("AvailabilityScript")
struct AvailabilityScriptTests {

    /// The app side of the pattern: its own closure, written with Apple's type. A real app
    /// would default it to `{ SystemLanguageModel.default.availability }`.
    struct Screen {
        var availability: () -> SystemLanguageModel.Availability

        var message: String {
            switch availability() {
            case .available: "Ready"
            case .unavailable(.deviceNotEligible): "This device can't run the model"
            case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence"
            case .unavailable(.modelNotReady): "Downloading the model"
            case .unavailable: "Unavailable"
            }
        }
    }

    @Test("Values come back in the order they were scripted")
    func valuesComeInOrder() {
        let script = AvailabilityScript(
            .unavailable(.appleIntelligenceNotEnabled),
            .unavailable(.modelNotReady),
            .available
        )
        #expect(script.next() == .unavailable(.appleIntelligenceNotEnabled))
        #expect(script.next() == .unavailable(.modelNotReady))
        #expect(script.next() == .available)
    }

    @Test("The last value repeats once the script is used up")
    func lastValueRepeats() {
        let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
        _ = script.next()
        for _ in 0..<10 {
            #expect(script.next() == .available)
        }
    }

    @Test("A single value answers every read")
    func singleValueAnswersEveryRead() {
        let script = AvailabilityScript(.unavailable(.deviceNotEligible))
        for _ in 0..<5 {
            #expect(script.next() == .unavailable(.deviceNotEligible))
        }
    }

    @Test("The array initializer behaves like the variadic one")
    func arrayInitializer() {
        let script = AvailabilityScript([.unavailable(.modelNotReady), .available])
        #expect(script.next() == .unavailable(.modelNotReady))
        #expect(script.next() == .available)
    }

    @Test("Reads are counted, and the script knows when it has been used up")
    func readsAreCounted() {
        let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
        #expect(script.readCount == 0)
        #expect(!script.isFinished)
        _ = script.next()
        #expect(script.readCount == 1)
        #expect(!script.isFinished)
        _ = script.next()
        #expect(script.isFinished)
        _ = script.next()
        #expect(script.readCount == 3)
        #expect(script.isFinished)
    }

    @Test("An app reaches its fallback screen without importing Assay")
    func drivesAnAppClosure() {
        let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
        let screen = Screen(availability: script.next)
        #expect(screen.message == "Downloading the model")
        #expect(screen.message == "Ready")
        #expect(screen.message == "Ready")
    }

    @Test("Concurrent reads each take one step and none is lost")
    func concurrentReads() async {
        let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
        let values = await withTaskGroup(of: SystemLanguageModel.Availability.self) { group in
            for _ in 0..<50 {
                group.addTask { script.next() }
            }
            var values: [SystemLanguageModel.Availability] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(script.readCount == 50)
        #expect(values.filter { $0 == .unavailable(.modelNotReady) }.count == 1)
        #expect(values.filter { $0 == .available }.count == 49)
    }
}

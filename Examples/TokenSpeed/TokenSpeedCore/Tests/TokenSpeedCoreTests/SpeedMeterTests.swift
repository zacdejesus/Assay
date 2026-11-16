import Testing
import TokenSpeedCore

@Suite("SpeedMeter")
struct SpeedMeterTests {

    @Test("Nothing to show before the first token")
    func emptyMeter() {
        var meter = SpeedMeter()
        meter.record(tokenCount: 0, elapsed: .seconds(1))
        #expect(meter.tokensPerSecond == nil)
        #expect(meter.timeToFirstToken == nil)
        #expect(meter.tokenCount == 0)
    }

    @Test("Speed leaves out the wait for the first token")
    func speedExcludesTheWait() {
        var meter = SpeedMeter()
        meter.record(tokenCount: 1, elapsed: .seconds(2))    // 2 s of waiting
        meter.record(tokenCount: 31, elapsed: .seconds(3))   // 30 tokens in the next second
        #expect(meter.timeToFirstToken == .seconds(2))
        #expect(meter.tokensPerSecond == 30)
        #expect(meter.tokenCount == 31)
    }

    @Test("Tokens that arrive with the first report count as the wait")
    func firstReportWithSeveralTokens() {
        var meter = SpeedMeter()
        meter.record(tokenCount: 5, elapsed: .seconds(1))
        meter.record(tokenCount: 25, elapsed: .seconds(2))
        #expect(meter.tokensPerSecond == 20)
    }

    @Test("With a single report, speed is all the tokens over all the time")
    func singleReport() {
        var meter = SpeedMeter()
        meter.record(tokenCount: 40, elapsed: .seconds(2))
        #expect(meter.tokensPerSecond == 20)
    }

    @Test("The speed follows the latest report")
    func speedUpdates() {
        var meter = SpeedMeter()
        meter.record(tokenCount: 1, elapsed: .seconds(1))
        meter.record(tokenCount: 11, elapsed: .seconds(2))
        #expect(meter.tokensPerSecond == 10)
        meter.record(tokenCount: 41, elapsed: .seconds(3))
        #expect(meter.tokensPerSecond == 20)
    }
}

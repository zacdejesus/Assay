/// Turns "how many output tokens so far, at what time" into the two numbers the app shows.
///
/// A value type with no clock of its own: the caller says how much time has passed. That
/// keeps the arithmetic testable with exact numbers.
public struct SpeedMeter: Sendable, Equatable {

    /// Output tokens reported so far.
    public private(set) var tokenCount = 0

    /// How long the first tokens took to arrive, measured from the request.
    /// The on-device model reports usage in batches (10 tokens at a time on macOS 27.2), so
    /// this is the time to the first batch, a little later than the very first token.
    public private(set) var timeToFirstToken: Duration?

    /// Tokens that arrived together with the first one. They belong to the wait, not to
    /// the generation that follows.
    private var tokensAtFirstReport = 0

    /// Time of the latest report, measured from the request.
    private var elapsed: Duration = .zero

    public init() {}

    /// Records the running total of output tokens, `elapsed` after the request was sent.
    /// Reports without tokens are ignored: the model hasn't started answering yet.
    public mutating func record(tokenCount: Int, elapsed: Duration) {
        guard tokenCount > 0 else { return }
        if timeToFirstToken == nil {
            timeToFirstToken = elapsed
            tokensAtFirstReport = tokenCount
        }
        self.tokenCount = tokenCount
        self.elapsed = elapsed
    }

    /// Generation speed: the tokens produced after the first report, divided by the time
    /// since it. The wait for the first token is left out, because it measures something
    /// else (loading the model, reading the prompt).
    ///
    /// If there has been only one report, there is no interval to measure, and the speed
    /// falls back to all the tokens over all the time. `nil` until something can be computed.
    public var tokensPerSecond: Double? {
        guard let timeToFirstToken else { return nil }
        let generated = tokenCount - tokensAtFirstReport
        let window = (elapsed - timeToFirstToken).seconds
        if generated > 0, window > 0 {
            return Double(generated) / window
        }
        let total = elapsed.seconds
        return total > 0 ? Double(tokenCount) / total : nil
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

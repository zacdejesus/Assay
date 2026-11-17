import FoundationModels

/// What the app says when the model can't be used.
public struct Fallback: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var symbol: String
    /// Whether checking again can help. A device that isn't eligible stays that way.
    public var canRetry: Bool

    public init(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        switch reason {
        case .deviceNotEligible:
            title = "This device can't run the model"
            detail = "Apple Intelligence needs a newer device."
            symbol = "iphone.slash"
            canRetry = false
        case .appleIntelligenceNotEnabled:
            title = "Apple Intelligence is off"
            detail = "Turn it on in Settings, then come back."
            symbol = "switch.2"
            canRetry = true
        case .modelNotReady:
            title = "The model is getting ready"
            detail = "It may still be downloading. This can take a few minutes."
            symbol = "arrow.down.circle"
            canRetry = true
        @unknown default:
            title = "The model isn't available"
            detail = "Try again later."
            symbol = "exclamationmark.triangle"
            canRetry = true
        }
    }
}

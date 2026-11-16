// AvailabilityScript: a scripted answer to "is the on-device model available?", for tests.
// Design and the reasons behind it: docs/decisions/0004-availability-simulation.md

import FoundationModels
import Synchronization

/// A sequence of availability values that a test hands to the app, one per read.
///
/// `SystemLanguageModel.default.availability` returns whatever the machine running the test
/// has, so the screens an app shows when the model is missing can't be reached from a test.
/// Availability isn't part of the `LanguageModel` protocol either, so ``FakeModel`` can't
/// simulate it.
///
/// The app reads availability through a closure of its own, written with Apple's type. It
/// doesn't import Assay:
///
/// ```swift
/// // App
/// var availability: () -> SystemLanguageModel.Availability = {
///     SystemLanguageModel.default.availability
/// }
/// ```
///
/// A test replaces that closure with a script:
///
/// ```swift
/// // Test
/// let script = AvailabilityScript(.unavailable(.modelNotReady), .available)
/// viewModel.availability = script.next
/// // First read: the model is still downloading. Every read after that: available.
/// ```
///
/// Each read returns the next value. When the script is used up, the last value is returned
/// on every further read: availability is a state, and a view may read it any number of
/// times. This is the opposite of ``FakeModel``, which fails when its responses run out.
///
/// A script is a reference type and is safe to read from any thread.
public final class AvailabilityScript: Sendable {

    public typealias Availability = SystemLanguageModel.Availability

    private let steps: [Availability]
    private let reads = Mutex(0)

    /// A script with at least one value. An empty script can't be written this way.
    public convenience init(_ first: Availability, _ rest: Availability...) {
        self.init([first] + rest)
    }

    /// A script from an array.
    /// - Precondition: `steps` is not empty. There would be nothing to answer with.
    public init(_ steps: [Availability]) {
        precondition(!steps.isEmpty, "AvailabilityScript needs at least one value")
        self.steps = steps
    }

    /// Returns the next value in the script, or the last one once the script is used up.
    ///
    /// Pass it where the app expects a closure: `viewModel.availability = script.next`.
    public func next() -> Availability {
        let index = reads.withLock { reads in
            defer { reads += 1 }
            return reads
        }
        return steps[min(index, steps.count - 1)]
    }

    /// How many times ``next()`` has been called.
    public var readCount: Int {
        reads.withLock { $0 }
    }

    /// Whether every value in the script has been returned at least once. A test can check
    /// this to confirm that the app actually reached the last state.
    public var isFinished: Bool {
        readCount >= steps.count
    }
}

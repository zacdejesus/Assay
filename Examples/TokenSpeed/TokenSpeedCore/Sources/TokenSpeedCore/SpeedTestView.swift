import SwiftUI

/// The whole UI: the fallback when the model can't be used, the speed test when it can.
public struct SpeedTestView: View {
    @Bindable private var test: SpeedTest
    @Environment(\.scenePhase) private var scenePhase

    public init(test: SpeedTest) {
        self.test = test
    }

    public var body: some View {
        Group {
            if case .unavailable(let reason) = test.screen {
                FallbackView(fallback: Fallback(reason)) { test.refreshAvailability() }
            } else {
                meter
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { test.refreshAvailability() }
        }
    }

    private var meter: some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
                Text(speedText)
                    .font(.system(size: 112, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: speedText)
                    .foregroundStyle(test.screen == .running ? Color.accentColor : Color.primary)
                Text("tokens per second")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 32) {
                stat("First tokens", firstTokenText)
                stat("Tokens", "\(test.meter.tokenCount)")
            }

            if !test.modelAssets.isEmpty {
                VStack(spacing: 2) {
                    ForEach(ModelAssets.labels(for: test.modelAssets), id: \.self) { label in
                        Text(label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Model assets")
            }

            ScrollView {
                Text(responseText)
                    .font(.callout)
                    .foregroundStyle(isFailure ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            TextField("Prompt", text: $test.prompt, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .disabled(test.screen == .running)

            Button {
                Task { await test.run() }
            } label: {
                Text(test.screen == .running ? "Measuring…" : "Run")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(test.screen == .running || test.prompt.isEmpty)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var speedText: String {
        guard let speed = test.meter.tokensPerSecond else { return "–" }
        return speed.formatted(.number.precision(.fractionLength(speed < 100 ? 1 : 0)))
    }

    private var firstTokenText: String {
        guard let time = test.meter.timeToFirstToken else { return "–" }
        return time.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
    }

    private var isFailure: Bool {
        if case .failed = test.screen { true } else { false }
    }

    private var responseText: String {
        if case .failed(let message) = test.screen { return message }
        return test.text
    }
}

struct FallbackView: View {
    var fallback: Fallback
    var checkAgain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: fallback.symbol)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(fallback.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(fallback.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if fallback.canRetry {
                Button("Check again", action: checkAgain)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
    }
}

#Preview("Downloading") {
    SpeedTestView(test: SpeedTest(availability: { .unavailable(.modelNotReady) }))
}

#Preview("Ready") {
    SpeedTestView(test: SpeedTest(availability: { .available }))
}

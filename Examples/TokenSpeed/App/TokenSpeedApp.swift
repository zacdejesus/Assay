import SwiftUI
import TokenSpeedCore

// The app is only this file. Everything else lives in TokenSpeedCore, where `swift test`
// can reach it. Note what isn't imported here: Assay.
@main
struct TokenSpeedApp: App {
    @State private var test = SpeedTest()

    var body: some Scene {
        WindowGroup {
            SpeedTestView(test: test)
        }
    }
}

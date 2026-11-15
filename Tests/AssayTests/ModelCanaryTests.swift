// The canary: fails when the on-device model is not the one this repo was last checked
// against. It doesn't mean anything is broken. It means the model changed, and that
// everything recorded or observed with the old one needs a second look.
//
// When it fails:
//   1. scripts/test.sh after-update      (full suite, new baseline, comparison)
//   2. Replace `knownAssetIDs` below with the IDs printed in the failure.
//   3. Add the new versions to docs/notes/environment.md, keeping the old ones.
//
// Live test, opt-in:  scripts/test.sh canary

import FoundationModels
import Testing

@Suite("Canary: has the on-device model changed?")
struct ModelCanaryTests {

    /// The model assets seen on 2026-11-15 with macOS 27.2 (26B123), sorted.
    /// Before that, on 2026-11-07 with macOS 27.0.1 (26A434), the main model was
    /// `...fm_api_generic_3b?variant=generic_sparse_16.1.0.13.103120,0`.
    static let knownAssetIDs = [
        "com.apple.fm.language.instruct_3b.fm_api_generic.draft?variant=generic_sparse_16.1000.81614.13.205144,0",
        "com.apple.fm.language.instruct_3b.fm_api_generic_3b?variant=generic_sparse_16.1000.0.13.103404,0",
        "com.apple.fm.language.instruct_3b.tokenizer?variant=generic_sparse_16.1000.0.13.205140,0",
    ]

    @Test(
        "The model assets are the ones this repo was last checked against",
        .enabled(if: Live.isEnabled, "Live test: needs ASSAY_LIVE=1 and Apple Intelligence")
    )
    func modelAssetsAreUnchanged() async throws {
        let run = try await Live.respond(to: "Reply with the single word: pong", options: Live.greedy())
        let current = run.assetIDs.map { "        \"\($0)\"," }.joined(separator: "\n")
        #expect(
            run.assetIDs == Self.knownAssetIDs,
            """
            The on-device model changed (system: \(run.systemVersion ?? "unknown")).
            Run `scripts/test.sh after-update`, then set knownAssetIDs to:
            \(current)
            """
        )
    }
}

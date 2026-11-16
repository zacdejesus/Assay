import Assay
import FoundationModels
import Testing
import TokenSpeedCore

@Suite("ModelAssets")
struct ModelAssetsTests {

    static let real = [
        "com.apple.fm.language.instruct_3b.fm_api_generic.draft?variant=generic_sparse_16.1000.81614.13.205144,0",
        "com.apple.fm.language.instruct_3b.fm_api_generic_3b?variant=generic_sparse_16.1000.0.13.103404,0",
        "com.apple.fm.language.instruct_3b.tokenizer?variant=generic_sparse_16.1000.0.13.205140,0",
    ]

    @Test("The shared prefix is dropped and the versions are kept whole")
    func labelsDropTheSharedPrefix() {
        #expect(ModelAssets.labels(for: Self.real) == [
            "fm_api_generic.draft?variant=generic_sparse_16.1000.81614.13.205144,0",
            "fm_api_generic_3b?variant=generic_sparse_16.1000.0.13.103404,0",
            "tokenizer?variant=generic_sparse_16.1000.0.13.205140,0",
        ])
    }

    @Test("A single identifier keeps its last name component")
    func singleIdentifier() {
        #expect(ModelAssets.labels(for: ["com.example.model?variant=1.2"]) == ["model?variant=1.2"])
    }

    @Test("Identifiers with nothing in common are shown whole")
    func nothingShared() {
        #expect(ModelAssets.labels(for: ["alpha.one", "beta.two"]) == ["alpha.one", "beta.two"])
        #expect(ModelAssets.labels(for: []) == [])
    }

    @Test("A model that reports no assets shows none")
    @MainActor
    func fakeModelHasNoAssets() async {
        let model = FakeModel("Hi.")
        let test = SpeedTest(availability: { .available }, makeSession: { LanguageModelSession(model: model) })
        await test.run()
        #expect(test.screen == .finished)
        #expect(test.modelAssets.isEmpty)
    }
}

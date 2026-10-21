import Testing
@testable import OMPCore

@Suite("The model list")
struct ModelInfoTests {
    @Test("a model served by a gateway names the vendor behind it")
    func namesTheVendor() throws {
        let model = try #require(ModelInfo(json: .object([
            "id": .string("anthropic/claude-3.7-sonnet"),
            "name": .string("Claude 3.7 Sonnet"),
            "provider": .string("openrouter"),
        ])))
        #expect(model.upstream == "anthropic")
        #expect(model.provider == "openrouter")
    }

    @Test("a model served directly names its provider")
    func namesItsProvider() throws {
        let model = try #require(ModelInfo(json: .object([
            "id": .string("claude-opus-4-6"),
            "name": .string("Claude Opus 4.6"),
            "provider": .string("google-antigravity"),
        ])))
        #expect(model.upstream == "google-antigravity")
    }

    @Test("the alias marker is not part of the vendor")
    func dropsTheAliasMarker() throws {
        let model = try #require(ModelInfo(json: .object([
            "id": .string("~anthropic/claude-opus-latest"),
            "name": .string("Claude Opus Latest"),
            "provider": .string("openrouter"),
        ])))
        #expect(model.upstream == "anthropic")
    }
}

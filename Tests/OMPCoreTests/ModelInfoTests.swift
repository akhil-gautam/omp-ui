import Testing
@testable import OMPCore

@Suite("The model list")
struct ModelInfoTests {
    @Test("a model is named by omp's selector")
    func usesOmpsSelector() throws {
        let model = try #require(ModelInfo(json: .object([
            "id": .string("~anthropic/claude-opus-latest"),
            "name": .string("Claude Opus Latest"),
            "provider": .string("openrouter"),
            "selector": .string("openrouter/~anthropic/claude-opus-latest"),
        ])))
        #expect(model.selector == "openrouter/~anthropic/claude-opus-latest")
    }

    @Test("without a selector, the provider and the id make one")
    func buildsTheSelector() throws {
        let model = try #require(ModelInfo(json: .object([
            "id": .string("claude-opus-5-5"),
            "name": .string("Claude Opus 5.5"),
            "provider": .string("anthropic"),
        ])))
        #expect(model.selector == "anthropic/claude-opus-5-5")
    }

    @Test("the same model from a subscription and from a gateway are two models")
    func aSubscriptionIsNotAGateway() throws {
        let subscription = ModelInfo(id: "claude-opus-5-5", name: "Claude Opus 5.5", provider: "anthropic")
        let gateway = ModelInfo(id: "anthropic/claude-opus-5.5", name: "Claude Opus 5.5", provider: "openrouter")
        #expect(subscription.name == gateway.name)
        #expect(subscription.selector != gateway.selector)
        #expect(gateway.selector.hasPrefix("openrouter/"))
    }

    @Test("one id offered by two providers is still two models")
    func anIdIsNotEnough() {
        let direct = ModelInfo(id: "claude-opus-4-6", name: "Claude Opus 4.6", provider: "anthropic")
        let antigravity = ModelInfo(id: "claude-opus-4-6", name: "Claude Opus 4.6", provider: "google-antigravity")
        #expect(direct.id == antigravity.id)
        #expect(direct.selector != antigravity.selector)
    }
}

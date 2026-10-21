import Testing
import OMPCore
@testable import OMPApp

@Suite("The model picker")
struct ModelListTests {
    /// A row as the composer builds it from a model.
    private func row(_ model: ModelInfo) -> Select.Item {
        Select.Item(id: model.selector, title: model.name, detail: model.selector, badge: model.provider)
    }

    private let subscription = ModelInfo(id: "claude-opus-5-5", name: "Claude Opus 5.5", provider: "anthropic")
    private let gateway = ModelInfo(id: "anthropic/claude-opus-5.5", name: "Claude Opus 5.5", provider: "openrouter")

    @Test("a model served through a gateway says so")
    func theGatewayIsNamed() {
        #expect(row(gateway).detail == "openrouter/anthropic/claude-opus-5.5")
        #expect(row(gateway).badge == "openrouter")
        #expect(row(subscription).detail == "anthropic/claude-opus-5-5")
        #expect(row(subscription).badge == "anthropic")
        #expect(row(subscription).id != row(gateway).id)
    }

    @Test("searching a vendor finds its own models and the gateways serving them")
    func searchFindsBoth() {
        #expect(Select.matches(row(subscription), "anthropic"))
        #expect(Select.matches(row(gateway), "anthropic"))
        #expect(Select.matches(row(gateway), "openrouter"))
        #expect(Select.matches(row(subscription), "openrouter") == false)
        #expect(Select.matches(row(subscription), "OPUS 5.5"))
    }

    @Test("a row's tooltip carries its selector")
    func theTooltipCarriesTheSelector() {
        #expect(row(gateway).tip == "Claude Opus 5.5 — openrouter/anthropic/claude-opus-5.5")
    }
}

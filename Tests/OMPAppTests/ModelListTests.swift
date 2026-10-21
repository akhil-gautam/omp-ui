import Testing
@testable import OMPApp

@Suite("The model list")
struct ModelListTests {
    /// A model served by openrouter, from Anthropic.
    private let servedByOpenrouter = Select.Item(
        id: "anthropic/claude-3.7-sonnet",
        title: "Claude 3.7 Sonnet",
        detail: "openrouter"
    )

    @Test("a model is found by the upstream that serves it")
    func foundByItsUpstream() {
        #expect(Select.matches(servedByOpenrouter, "anthropic"))
        #expect(Select.matches(servedByOpenrouter, "claude"))
        #expect(Select.matches(servedByOpenrouter, "openrouter"))
        #expect(Select.matches(servedByOpenrouter, "3.7 sonnet"))
        #expect(Select.matches(servedByOpenrouter, "ANTHROPIC"))
    }

    @Test("a model is not found by what it is not")
    func notFoundByWhatItIsNot() {
        #expect(Select.matches(servedByOpenrouter, "gemini") == false)
        #expect(Select.matches(servedByOpenrouter, "google") == false)
    }

    @Test("a row's tooltip says where the model comes from")
    func theTooltipSaysTheUpstream() {
        #expect(servedByOpenrouter.tip == "Claude 3.7 Sonnet — openrouter  ·  anthropic/claude-3.7-sonnet")
        // A model whose id is just its name has no upstream to add.
        let direct = Select.Item(id: "claude-opus-4-6", title: "Claude Opus 4.6", detail: "google-antigravity")
        #expect(direct.tip == "Claude Opus 4.6 — google-antigravity")
    }
}

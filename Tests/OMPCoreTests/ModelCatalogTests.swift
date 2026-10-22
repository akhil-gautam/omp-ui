import Foundation
import Testing
@testable import OMPCore

@Suite("Ordering models by models.dev")
struct ModelCatalogTests {
    /// A slice of models.dev's api.json, in its own shape.
    private let catalog: ModelCatalog = {
        let json = """
        {
          "anthropic": {"id": "anthropic", "name": "Anthropic", "models": {
            "claude-opus-4-6": {"id": "claude-opus-4-6", "release_date": "2026-02-04"},
            "claude-haiku-4-5": {"id": "claude-haiku-4-5", "release_date": "2025-10-15"}
          }},
          "openrouter": {"id": "openrouter", "name": "OpenRouter", "models": {
            "anthropic/claude-opus-4.6": {"id": "anthropic/claude-opus-4.6", "release_date": "2026-02-05",
                                          "canonical_model_id": "anthropic/claude-opus-4-6"},
            "openai/gpt-5": {"id": "openai/gpt-5", "release_date": "2025-08-07", "canonical_model_id": "openai/gpt-5"}
          }},
          "preview-host": {"id": "preview-host", "name": "Preview Host", "models": {
            "claude-opus-4.6": {"id": "claude-opus-4.6", "release_date": "2025-08-26", "canonical_model_id": "anthropic/claude-opus-4-6"}
          }}
        }
        """
        return try! ModelCatalog(apiJSON: Data(json.utf8))
    }()

    private func model(_ provider: String, _ id: String) -> ModelInfo {
        ModelInfo(id: id, name: id, provider: provider)
    }

    @Test("each provider's models come newest first, the undated after, in natural order")
    func newestFirst() {
        let listed = [
            model("anthropic", "claude-3-5-sonnet-20240620"),
            model("anthropic", "claude-3-5-sonnet-20241022"),
            model("anthropic", "claude-fable-5"),
            model("anthropic", "claude-haiku-4-5"),
            model("anthropic", "claude-fable-5-1"),
            model("anthropic", "claude-opus-4-6"),
        ]
        #expect(catalog.ordered(listed).map(\.id) == [
            "claude-opus-4-6",              // 2026-02-04, from models.dev
            "claude-haiku-4-5",             // 2025-10-15
            "claude-3-5-sonnet-20241022",   // from the date in its id
            "claude-3-5-sonnet-20240620",
            "claude-fable-5-1",             // no date: 5.1 above 5
            "claude-fable-5",
        ])
    }

    @Test("providers stay in omp's order, each sorted within itself")
    func providersKeepTheirOrder() {
        let listed = [
            model("openrouter", "openai/gpt-5"),
            model("anthropic", "claude-haiku-4-5"),
            model("openrouter", "anthropic/claude-opus-4.6"),
            model("anthropic", "claude-opus-4-6"),
        ]
        #expect(catalog.ordered(listed).map(\.selector) == [
            "openrouter/anthropic/claude-opus-4.6",
            "openrouter/openai/gpt-5",
            "anthropic/claude-opus-4-6",
            "anthropic/claude-haiku-4-5",
        ])
    }

    @Test("a provider models.dev does not list is dated by the maker's own entry")
    func datedByTheMaker() {
        // omp's google-antigravity serves Anthropic's model under its own id;
        // a reseller's earlier preview date does not win over Anthropic's.
        #expect(catalog.releaseDate(of: model("google-antigravity", "claude-opus-4-6")) == "2026-02-04")
        #expect(catalog.releaseDate(of: model("google-antigravity", "gpt-oss-120b")) == nil)
    }

    @Test("a row's logo is its maker's: named in a gateway's id, or recorded by models.dev")
    func makersForLogos() {
        #expect(catalog.maker(of: model("openrouter", "anthropic/claude-opus-4.6")) == "anthropic")
        #expect(catalog.maker(of: model("google-antigravity", "claude-opus-4-6")) == "anthropic")
        #expect(catalog.maker(of: model("google-antigravity", "gpt-oss-120b")) == "google-antigravity")
        #expect(catalog.name(ofProvider: "anthropic") == "Anthropic")
    }

    @Test("a date is read from an id only when it is one")
    func datesInIDs() {
        #expect(ModelCatalog.dateInID("claude-3-5-sonnet-20240620") == "2024-06-20")
        #expect(ModelCatalog.dateInID("minimax-m3.1-flash:free") == nil)
        #expect(ModelCatalog.dateInID("model-20241399") == nil)
    }

    @Test("the compact catalog kept on disk reads back the same")
    func compactRoundTrip() throws {
        let data = try JSONEncoder().encode(catalog)
        #expect(try JSONDecoder().decode(ModelCatalog.self, from: data) == catalog)
    }
}

import Foundation

/// What models.dev knows about models: when each was released, who makes it,
/// and what each provider is called — for listing omp's models newest first,
/// provider by provider, with their logos.
///
/// Built from models.dev's `api.json` and kept in a compact form, since the
/// whole catalog is several megabytes and only these facts are used.
public struct ModelCatalog: Sendable, Codable, Equatable {
    /// Release dates, `yyyy-mm-dd`, by provider and then by normalised model
    /// id.
    var dates: [String: [String: String]]
    /// The earliest release date of a model by its normalised id, across
    /// every provider that serves it.
    var datesByModel: [String: String]
    /// The maker of a model by its normalised id, where models.dev names one.
    var makers: [String: String]
    /// Provider names by id.
    var names: [String: String]

    public init(dates: [String: [String: String]] = [:], datesByModel: [String: String] = [:], makers: [String: String] = [:], names: [String: String] = [:]) {
        self.dates = dates
        self.datesByModel = datesByModel
        self.makers = makers
        self.names = names
    }

    /// Reads models.dev's `api.json`: provider ids mapping to a name and
    /// their models, each with an optional `release_date` and
    /// `canonical_model_id` of the form `maker/model`.
    public init(apiJSON data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        self.init()
        for (providerID, value) in root {
            guard let provider = value as? [String: Any] else { continue }
            if let name = provider["name"] as? String { names[providerID] = name }
            guard let models = provider["models"] as? [String: Any] else { continue }
            var providerDates: [String: String] = [:]
            for (modelID, value) in models {
                guard let model = value as? [String: Any] else { continue }
                let canonical = model["canonical_model_id"] as? String
                let keys = Set([Self.normalize(modelID)] + (canonical.map { [Self.normalize($0)] } ?? []))
                if let maker = canonical.flatMap(Self.maker(of:)) {
                    for key in keys where makers[key] == nil { makers[key] = maker }
                }
                guard let date = model["release_date"] as? String, date.count >= 7 else { continue }
                let own = Self.normalize(modelID)
                if providerDates[own].map({ date < $0 }) ?? true { providerDates[own] = date }
                for key in keys where (datesByModel[key].map { date < $0 } ?? true) {
                    datesByModel[key] = date
                }
            }
            if !providerDates.isEmpty { dates[providerID] = providerDates }
        }
    }

    // MARK: - Facts about one model

    /// When a model came out: as its provider lists it, else as its maker
    /// does — a reseller may list an earlier preview — else as any provider
    /// serving the same model does, else the date written into its id.
    public func releaseDate(of model: ModelInfo) -> String? {
        let key = Self.normalize(model.id)
        return dates[model.provider]?[key]
            ?? dates[maker(of: model)]?[key]
            ?? datesByModel[key]
            ?? Self.dateInID(model.id)
    }

    /// Who makes a model, for its logo: the maker a gateway names in the id
    /// (`anthropic/…` through OpenRouter), else the one models.dev records,
    /// else the provider serving it.
    public func maker(of model: ModelInfo) -> String {
        if model.id.contains("/"), let maker = Self.maker(of: model.id) { return maker }
        return makers[Self.normalize(model.id)] ?? model.provider
    }

    /// What a provider is called, by models.dev, or its id.
    public func name(ofProvider id: String) -> String? { names[id] }

    // MARK: - Order

    /// omp's models, provider by provider in the order omp lists them, each
    /// provider's newest first. Models without a date follow the dated ones,
    /// in descending natural order of their ids — which puts `v2` above the
    /// first, and `5.1` above `5`.
    public func ordered(_ models: [ModelInfo]) -> [ModelInfo] {
        var providers: [String] = []
        var groups: [String: [ModelInfo]] = [:]
        for model in models {
            if groups[model.provider] == nil { providers.append(model.provider) }
            groups[model.provider, default: []].append(model)
        }
        return providers.flatMap { provider in
            groups[provider, default: []]
                .map { ($0, releaseDate(of: $0)) }
                .sorted { left, right in
                    switch (left.1, right.1) {
                    case let (a?, b?) where a != b: return a > b
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return left.0.id.localizedStandardCompare(right.0.id) == .orderedDescending
                    }
                }
                .map(\.0)
        }
    }

    // MARK: - Matching ids

    /// An id reduced to what names the model itself, so the same model
    /// matches across providers: no maker prefix, no `~`, no `:free`-style
    /// variant, lower case, dots as dashes (`claude-opus-4.6` is
    /// `claude-opus-4-6`).
    static func normalize(_ id: String) -> String {
        var name = id.lowercased()
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if let colon = name.firstIndex(of: ":") { name = String(name[..<colon]) }
        if name.hasPrefix("~") { name.removeFirst() }
        return name.replacingOccurrences(of: ".", with: "-")
    }

    /// The maker in a `maker/model` id.
    static func maker(of id: String) -> String? {
        guard let slash = id.firstIndex(of: "/") else { return nil }
        var maker = String(id[..<slash]).lowercased()
        if maker.hasPrefix("~") { maker.removeFirst() }
        return maker.isEmpty ? nil : maker
    }

    /// A date written into an id as eight digits, `…-20240620`.
    static func dateInID(_ id: String) -> String? {
        let digits = id.split(whereSeparator: { !$0.isNumber })
        guard let run = digits.last(where: { $0.count == 8 && ($0.hasPrefix("19") || $0.hasPrefix("20")) }) else { return nil }
        let text = String(run)
        let year = text.prefix(4), month = text.dropFirst(4).prefix(2), day = text.suffix(2)
        guard let m = Int(month), (1...12).contains(m), let d = Int(day), (1...31).contains(d) else { return nil }
        return "\(year)-\(month)-\(day)"
    }
}

/// models.dev's catalog and logos, fetched at most once a day and kept on
/// disk, so the picker is ordered and drawn without waiting on the network.
public enum ModelsDev {
    public static let catalogURL = URL(string: "https://models.dev/api.json")!

    public static func logoURL(for provider: String) -> URL {
        URL(string: "https://models.dev/logos/\(provider).svg")!
    }

    /// Where the compact catalog and the logos are kept.
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("omp-ui/models.dev", isDirectory: true)
    }

    /// Named by the form it is kept in, so a copy in an older form is never
    /// read as the current one.
    static var catalogFile: URL { directory.appendingPathComponent("catalog-2.json") }

    /// The catalog kept from the last fetch, and how old it is.
    public static func cached() -> (catalog: ModelCatalog, age: TimeInterval)? {
        guard let data = try? Data(contentsOf: catalogFile),
              let catalog = try? JSONDecoder().decode(ModelCatalog.self, from: data) else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: catalogFile.path)[.modificationDate] as? Date) ?? .distantPast
        return (catalog, Date().timeIntervalSince(modified))
    }

    /// Fetches the catalog and keeps its compact form.
    public static func fetch() async throws -> ModelCatalog {
        let (data, response) = try await URLSession.shared.data(from: catalogURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let catalog = try ModelCatalog(apiJSON: data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(catalog).write(to: catalogFile, options: .atomic)
        return catalog
    }

    /// A provider's logo, an SVG drawn in `currentColor`: from disk, else
    /// fetched and kept.
    public static func logo(for provider: String) async -> Data? {
        let file = directory.appendingPathComponent("logos/\(provider).svg")
        if let data = try? Data(contentsOf: file) { return data }
        guard let (data, response) = try? await URLSession.shared.data(from: logoURL(for: provider)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}

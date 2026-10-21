import Foundation

/// A model, as omp describes it.
///
/// omp names a model by its selector, `provider/id`: the provider is the one
/// that serves and bills it, so `anthropic/claude-opus-5-5` runs on an
/// Anthropic login while `openrouter/anthropic/claude-opus-5.5` is billed to
/// OpenRouter. The bare id is not unique — the same id can be offered by two
/// providers — so the selector is what tells models apart.
public struct ModelInfo: Sendable, Equatable {
    public var id: String
    public var name: String
    public var provider: String
    public var selector: String
    public var contextWindow: Int?

    public init(id: String, name: String, provider: String, selector: String? = nil, contextWindow: Int? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.selector = selector ?? (provider.isEmpty ? id : "\(provider)/\(id)")
        self.contextWindow = contextWindow
    }

    public init?(json: JSONValue) {
        guard let id = json["id"].optionalString else { return nil }
        let provider = json["provider"].optionalString ?? ""
        self.init(
            id: id,
            name: json["name"].optionalString ?? id,
            provider: provider,
            selector: json["selector"].optionalString,
            contextWindow: json["contextWindow"].exactInteger
        )
    }
}

/// How much of the context window is in use.
public struct ContextUsage: Sendable, Equatable {
    public var tokens: Int
    public var contextWindow: Int
    /// A percentage, not a fraction: omp writes 0.7 for a tenth of a percent.
    public var percent: Double

    public init(tokens: Int, contextWindow: Int, percent: Double) {
        self.tokens = tokens
        self.contextWindow = contextWindow
        self.percent = percent
    }

    public init?(json: JSONValue) {
        guard json["tokens"].exactInteger != nil, json["contextWindow"].exactInteger != nil else { return nil }
        self.tokens = json["tokens"].int
        self.contextWindow = json["contextWindow"].int
        self.percent = json["percent"].double ?? 0
    }
}

/// One task in a plan.
public struct TodoItem: Sendable, Identifiable, Equatable {
    public var id: String { content }
    public var content: String
    public var status: String
    public var blocker: String?

    public init(content: String, status: String, blocker: String? = nil) {
        self.content = content
        self.status = status
        self.blocker = blocker
    }

    public init?(json: JSONValue) {
        guard let content = json["content"].optionalString else { return nil }
        self.content = content
        self.status = json["status"].string.isEmpty ? "pending" : json["status"].string
        self.blocker = json["blocker"].optionalString
    }

    public var isDone: Bool { status == "completed" || status == "abandoned" }
    public var isBlocked: Bool { status == "blocked" }
}

/// A group of tasks.
public struct TodoPhase: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var tasks: [TodoItem]

    public init(name: String, tasks: [TodoItem]) {
        self.name = name
        self.tasks = tasks
    }

    public init?(json: JSONValue) {
        guard let name = json["name"].optionalString else { return nil }
        self.name = name
        self.tasks = json["tasks"].array.compactMap(TodoItem.init(json:))
    }
}

/// One of omp's slash commands.
public struct SlashCommand: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var source: String
    public var description: String?

    public init(name: String, source: String, description: String? = nil) {
        self.name = name
        self.source = source
        self.description = description
    }

    public init?(json: JSONValue) {
        guard let name = json["name"].optionalString else { return nil }
        self.name = name
        self.source = json["source"].string
        self.description = json["description"].optionalString
    }
}

/// The messages waiting for the agent.
public struct Queue: Sendable, Equatable {
    public var steering: [String]
    public var followUp: [String]

    public init(steering: [String] = [], followUp: [String] = []) {
        self.steering = steering
        self.followUp = followUp
    }

    public var count: Int { steering.count + followUp.count }
    public var isEmpty: Bool { count == 0 }
}

/// How the session behaves.
public enum SessionMode: String, CaseIterable, Sendable {
    /// A steer lands on the running turn straight away.
    case interactive
    /// The agent finishes what it is doing first.
    case autopilot

    public var label: String {
        switch self {
        case .interactive: "Interactive"
        case .autopilot: "Autopilot"
        }
    }

    public var hint: String {
        switch self {
        case .interactive: "A steer lands on the running turn; messages queue up"
        case .autopilot: "The agent finishes what it is doing first; messages queue up"
        }
    }
}

/// A dialog the agent is waiting on.
public struct UIRequest: Sendable, Identifiable, Equatable {
    public struct Option: Sendable, Equatable, Identifiable {
        public var id: String { label }
        public var label: String
        public var description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }

    public var id: String
    public var method: String
    public var title: String?
    public var message: String?
    public var options: [Option]
    public var placeholder: String?
    public var launchURL: String?
    public var multi: Bool
    public var recommended: Int?

    public init(id: String, method: String, title: String? = nil, message: String? = nil, options: [Option] = [], placeholder: String? = nil, launchURL: String? = nil, multi: Bool = false, recommended: Int? = nil) {
        self.id = id
        self.method = method
        self.title = title
        self.message = message
        self.options = options
        self.placeholder = placeholder
        self.launchURL = launchURL
        self.multi = multi
        self.recommended = recommended
    }

    public init?(json: JSONValue) {
        guard let id = json["id"].optionalString else { return nil }
        let method = json["method"].string
        guard ["select", "confirm", "input", "editor", "ask", "open_url"].contains(method) else { return nil }
        self.id = id
        self.method = method
        self.title = json["title"].optionalString
        self.message = json["message"].optionalString
        self.options = json["options"].array.map { option in
            Option(label: option["label"].string, description: option["description"].optionalString)
        }
        self.placeholder = json["placeholder"].optionalString
        self.launchURL = json["launchUrl"].optionalString
        self.multi = json["multi"].bool
        self.recommended = json["recommended"].exactInteger
    }

    /// The answer the app sends back.
    public func answer(_ value: String, cancelled: Bool = false) -> [String: JSONValue] {
        if cancelled { return ["type": .string("cancelled"), "timedOut": .bool(false)] }
        switch method {
        case "select", "ask":
            return ["type": .string("select"), "option": .string(value)]
        case "confirm":
            return ["type": .string("confirm"), "confirmed": .bool(value == "yes")]
        case "input", "editor":
            return ["type": .string("value"), "value": .string(value)]
        default:
            return ["type": .string("cancelled"), "timedOut": .bool(false)]
        }
    }
}

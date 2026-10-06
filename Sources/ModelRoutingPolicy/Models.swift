import Foundation

/// List price for a model, in US dollars per million tokens.
public struct ModelPrice: Hashable, Sendable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double

    public init(inputPerMTok: Double, outputPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
    }

    /// Dollar cost of one call with the given token counts.
    public func cost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(inputTokens) / 1_000_000 * inputPerMTok
            + Double(outputTokens) / 1_000_000 * outputPerMTok
    }
}

public struct Model: Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let price: ModelPrice

    public init(id: String, displayName: String, price: ModelPrice) {
        self.id = id
        self.displayName = displayName
        self.price = price
    }
}

/// Reasoning effort is part of the routing decision, not a global setting.
public enum Effort: String, CaseIterable, Hashable, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: Effort, rhs: Effort) -> Bool { lhs.rank < rhs.rank }
}

/// A model pinned to an effort level. This is the unit a policy routes to.
public struct ModelChoice: Hashable, Sendable, CustomStringConvertible {
    public let model: Model
    public let effort: Effort

    public init(_ model: Model, _ effort: Effort) {
        self.model = model
        self.effort = effort
    }

    public var description: String { "\(model.displayName) · \(effort.rawValue)" }

    /// Stable key used for deterministic tie-breaking.
    var sortKey: String { "\(model.id)#\(effort.rawValue)" }
}

/// List prices from Anthropic's pricing docs (October 2026).
/// https://platform.claude.com/docs/en/about-claude/pricing
public enum Catalog {
    public static let opus55 = Model(
        id: "claude-opus-5-5", displayName: "Opus 5.5",
        price: ModelPrice(inputPerMTok: 4, outputPerMTok: 20))
    public static let sonnet55 = Model(
        id: "claude-sonnet-5-5", displayName: "Sonnet 5.5",
        price: ModelPrice(inputPerMTok: 2, outputPerMTok: 10))
    /// Sonnet 5.5 shipped at unchanged pricing, so Sonnet 5 shares the same list price.
    public static let sonnet5 = Model(
        id: "claude-sonnet-5", displayName: "Sonnet 5",
        price: ModelPrice(inputPerMTok: 2, outputPerMTok: 10))
}

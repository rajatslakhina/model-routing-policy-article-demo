import Foundation

/// The kinds of work a team actually hands to its coding agent.
public enum TaskClass: String, CaseIterable, Hashable, Sendable, Identifiable {
    case architecturePlanning
    case ambiguousRefactor
    case mechanicalMigration
    case buildFixLoop
    case testGeneration

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .architecturePlanning: return "Architecture planning"
        case .ambiguousRefactor: return "Ambiguous refactor"
        case .mechanicalMigration: return "Mechanical migration"
        case .buildFixLoop: return "Xcode build-fix loop"
        case .testGeneration: return "Test generation"
        }
    }
}

/// One row of the team's eval suite: a model choice run against a set of
/// real tasks of one class. Token counts are per-attempt averages.
public struct EvalResult: Hashable, Sendable {
    public let choice: ModelChoice
    public let taskClass: TaskClass
    public let attempts: Int
    public let resolved: Int
    public let inputTokensPerAttempt: Int
    public let outputTokensPerAttempt: Int

    public init(_ choice: ModelChoice, _ taskClass: TaskClass,
                attempts: Int, resolved: Int,
                inputTokens: Int, outputTokens: Int) {
        precondition(attempts > 0, "an eval row needs at least one attempt")
        precondition((0...attempts).contains(resolved), "resolved must be within 0...attempts")
        self.choice = choice
        self.taskClass = taskClass
        self.attempts = attempts
        self.resolved = resolved
        self.inputTokensPerAttempt = inputTokens
        self.outputTokensPerAttempt = outputTokens
    }

    /// Fraction of attempts that a reviewer accepted as resolved.
    public var resolveRate: Double { Double(resolved) / Double(attempts) }

    /// Model spend for one attempt, at list price.
    public var costPerAttempt: Double {
        choice.model.price.cost(inputTokens: inputTokensPerAttempt,
                                outputTokens: outputTokensPerAttempt)
    }

    /// Model spend divided by resolved tasks. `nil` when nothing resolved:
    /// the honest answer is "infinite", not zero.
    public var costPerResolved: Double? {
        guard resolved > 0 else { return nil }
        return costPerAttempt * Double(attempts) / Double(resolved)
    }
}

/// A snapshot of the eval suite, taken whenever a model ships.
public struct EvalSuite: Sendable {
    public let label: String
    public let results: [EvalResult]

    public init(label: String, results: [EvalResult]) {
        self.label = label
        self.results = results
    }

    public func result(for choice: ModelChoice, _ taskClass: TaskClass) -> EvalResult? {
        results.first { $0.choice == choice && $0.taskClass == taskClass }
    }

    public func results(for taskClass: TaskClass) -> [EvalResult] {
        results.filter { $0.taskClass == taskClass }
    }

    /// Every distinct model choice in the suite, in a stable order.
    public var choices: [ModelChoice] {
        var seen = Set<ModelChoice>()
        return results.compactMap { seen.insert($0.choice).inserted ? $0.choice : nil }
    }
}

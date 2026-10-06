import Foundation

/// What changed for one task class when the suite was re-run on a new release.
public struct ClassChange: Hashable, Sendable, Identifiable {
    public let taskClass: TaskClass
    public let current: PolicyEntry?
    public let candidate: PolicyEntry?

    public var id: TaskClass { taskClass }

    public var flipped: Bool { current?.route != candidate?.route }

    /// True when the first model a task goes to changed, not just the escalation.
    public var primaryFlipped: Bool { current?.route.primary != candidate?.route.primary }

    /// Change in agent-resolve rate, in percentage points (candidate minus current).
    public var resolveRateDeltaPoints: Double {
        ((candidate?.economics.agentResolveRate ?? 0) - (current?.economics.agentResolveRate ?? 0)) * 100
    }

    /// Change in expected cost per task, in dollars (candidate minus current).
    public var costDelta: Double {
        (candidate?.economics.expectedCostPerTask ?? 0) - (current?.economics.expectedCostPerTask ?? 0)
    }
}

public enum GateVerdict: Hashable, Sendable {
    /// Adopt the candidate policy. Carries the expected monthly saving (can be negative).
    case adopt(monthlySaving: Double)
    /// Keep the current policy: these classes would lose more resolve rate than allowed.
    case hold(regressions: [TaskClass])
}

public struct ReleaseReport: Sendable {
    public let current: RoutingPolicy
    public let candidate: RoutingPolicy
    public let changes: [ClassChange]
    public let currentMonthlyCost: Double
    public let candidateMonthlyCost: Double
    public let verdict: GateVerdict

    public var flippedClasses: [TaskClass] { changes.filter(\.flipped).map(\.taskClass) }
}

/// Re-validates the routing policy whenever a model ships. The policy changes on
/// evidence from the team's own suite, not on launch-day benchmarks.
public enum ReleaseGate {
    /// - Parameter maxResolveRegressionPoints: largest drop in agent-resolve rate,
    ///   in percentage points, any single class may take to save money.
    public static func evaluate(current currentSuite: EvalSuite,
                                candidate candidateSuite: EvalSuite,
                                mix: [TaskClass: Int],
                                assumptions: Assumptions = Assumptions(),
                                maxResolveRegressionPoints: Double = 2) -> ReleaseReport {
        let current = PolicyBuilder.derive(from: currentSuite, assumptions: assumptions)
        let candidate = PolicyBuilder.derive(from: candidateSuite, assumptions: assumptions)

        let changes = TaskClass.allCases.map {
            ClassChange(taskClass: $0, current: current.entry(for: $0), candidate: candidate.entry(for: $0))
        }
        let regressions = changes
            .filter { $0.resolveRateDeltaPoints < -maxResolveRegressionPoints }
            .map(\.taskClass)

        let currentCost = current.monthlyCost(mix: mix)
        let candidateCost = candidate.monthlyCost(mix: mix)
        let verdict: GateVerdict = regressions.isEmpty
            ? .adopt(monthlySaving: currentCost - candidateCost)
            : .hold(regressions: regressions)

        return ReleaseReport(current: current, candidate: candidate, changes: changes,
                             currentMonthlyCost: currentCost, candidateMonthlyCost: candidateCost,
                             verdict: verdict)
    }
}

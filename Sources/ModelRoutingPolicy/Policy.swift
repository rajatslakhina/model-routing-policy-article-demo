import Foundation

/// The economic assumptions a lead has to write down instead of leaving implicit.
public struct Assumptions: Hashable, Sendable {
    /// What a failed agent attempt costs once a human has to pick it up:
    /// reading the bad diff, throwing it away, doing the task by hand.
    public var humanEscalationCost: Double
    /// A task the primary model failed is harder than average, so the fallback's
    /// measured resolve rate is multiplied by this factor (0...1) on escalation.
    public var fallbackHardnessDiscount: Double
    /// No route is allowed below this agent-resolve rate, however cheap it is.
    public var minimumAgentResolveRate: Double

    public init(humanEscalationCost: Double = 60,
                fallbackHardnessDiscount: Double = 0.5,
                minimumAgentResolveRate: Double = 0.80) {
        self.humanEscalationCost = humanEscalationCost
        self.fallbackHardnessDiscount = min(max(fallbackHardnessDiscount, 0), 1)
        self.minimumAgentResolveRate = minimumAgentResolveRate
    }
}

/// Where one class of task goes: a primary choice and an optional escalation.
public struct Route: Hashable, Sendable, CustomStringConvertible {
    public let primary: ModelChoice
    public let fallback: ModelChoice?

    public init(primary: ModelChoice, fallback: ModelChoice? = nil) {
        self.primary = primary
        self.fallback = fallback
    }

    public var description: String {
        guard let fallback else { return primary.description }
        return "\(primary) → \(fallback)"
    }
}

/// The numbers behind a route, computed from eval results and assumptions.
public struct RouteEconomics: Hashable, Sendable {
    public let route: Route
    /// Probability the task ends resolved by an agent (primary or fallback).
    public let agentResolveRate: Double
    /// Expected model spend per task, including the fallback call when it fires.
    public let expectedModelSpend: Double
    /// Expected model spend plus expected human escalation cost, per task.
    public let expectedCostPerTask: Double

    public var expectedHumanCost: Double { expectedCostPerTask - expectedModelSpend }
}

public enum Economics {
    /// Prices a route against the suite. Returns `nil` if any leg was not evaluated
    /// for this class: an unmeasured route is not a cheap route.
    public static func price(_ route: Route, for taskClass: TaskClass,
                             in suite: EvalSuite, assumptions: Assumptions) -> RouteEconomics? {
        guard let a = suite.result(for: route.primary, taskClass) else { return nil }
        let pA = a.resolveRate
        let h = assumptions.humanEscalationCost

        guard let fallbackChoice = route.fallback else {
            let spend = a.costPerAttempt
            return RouteEconomics(route: route, agentResolveRate: pA,
                                  expectedModelSpend: spend,
                                  expectedCostPerTask: spend + (1 - pA) * h)
        }
        guard let b = suite.result(for: fallbackChoice, taskClass) else { return nil }
        let pB = b.resolveRate * assumptions.fallbackHardnessDiscount
        let spend = a.costPerAttempt + (1 - pA) * b.costPerAttempt
        let human = (1 - pA) * (1 - pB) * h
        return RouteEconomics(route: route, agentResolveRate: pA + (1 - pA) * pB,
                              expectedModelSpend: spend,
                              expectedCostPerTask: spend + human)
    }
}

public struct PolicyEntry: Hashable, Sendable, Identifiable {
    public let taskClass: TaskClass
    public let economics: RouteEconomics
    /// True when no route met the resolve-rate floor and the best available was used.
    public let belowFloor: Bool

    public var id: TaskClass { taskClass }
    public var route: Route { economics.route }
}

/// A routing policy: one route per task class, derived from evidence.
public struct RoutingPolicy: Sendable {
    public let suiteLabel: String
    public let assumptions: Assumptions
    public let entries: [PolicyEntry]

    public func entry(for taskClass: TaskClass) -> PolicyEntry? {
        entries.first { $0.taskClass == taskClass }
    }

    /// Expected monthly cost for a task mix (tasks per month per class).
    public func monthlyCost(mix: [TaskClass: Int]) -> Double {
        entries.reduce(0) { total, entry in
            total + Double(mix[entry.taskClass] ?? 0) * entry.economics.expectedCostPerTask
        }
    }

    /// Expected monthly model spend only, the number most dashboards show.
    public func monthlyModelSpend(mix: [TaskClass: Int]) -> Double {
        entries.reduce(0) { total, entry in
            total + Double(mix[entry.taskClass] ?? 0) * entry.economics.expectedModelSpend
        }
    }
}

public enum PolicyBuilder {
    /// Every primary/fallback combination the suite can price for one class.
    public static func candidateRoutes(for taskClass: TaskClass, in suite: EvalSuite) -> [Route] {
        let choices = suite.results(for: taskClass).map(\.choice)
        var routes: [Route] = []
        for primary in choices {
            routes.append(Route(primary: primary))
            for fallback in choices where fallback != primary {
                routes.append(Route(primary: primary, fallback: fallback))
            }
        }
        return routes
    }

    /// Picks, per class, the cheapest expected-cost route that clears the
    /// resolve-rate floor. If nothing clears it, picks the highest resolve rate
    /// and marks the entry so a human sees it.
    public static func derive(from suite: EvalSuite, assumptions: Assumptions = Assumptions()) -> RoutingPolicy {
        var entries: [PolicyEntry] = []
        for taskClass in TaskClass.allCases {
            let priced = candidateRoutes(for: taskClass, in: suite).compactMap {
                Economics.price($0, for: taskClass, in: suite, assumptions: assumptions)
            }
            guard !priced.isEmpty else { continue }

            let eligible = priced.filter { $0.agentResolveRate >= assumptions.minimumAgentResolveRate }
            if let best = eligible.min(by: cheaper) {
                entries.append(PolicyEntry(taskClass: taskClass, economics: best, belowFloor: false))
            } else if let best = priced.max(by: { $0.agentResolveRate < $1.agentResolveRate }) {
                entries.append(PolicyEntry(taskClass: taskClass, economics: best, belowFloor: true))
            }
        }
        return RoutingPolicy(suiteLabel: suite.label, assumptions: assumptions, entries: entries)
    }

    /// A single model for everything: the policy most teams have by default.
    public static func uniform(_ choice: ModelChoice, suite: EvalSuite,
                               assumptions: Assumptions = Assumptions()) -> RoutingPolicy {
        let entries = TaskClass.allCases.compactMap { taskClass -> PolicyEntry? in
            guard let economics = Economics.price(Route(primary: choice), for: taskClass,
                                                  in: suite, assumptions: assumptions) else { return nil }
            return PolicyEntry(taskClass: taskClass, economics: economics,
                               belowFloor: economics.agentResolveRate < assumptions.minimumAgentResolveRate)
        }
        return RoutingPolicy(suiteLabel: "\(suite.label) · all \(choice)",
                             assumptions: assumptions, entries: entries)
    }

    /// Cheaper expected cost wins; ties go to the simpler route, then to a stable key.
    static func cheaper(_ lhs: RouteEconomics, _ rhs: RouteEconomics) -> Bool {
        let epsilon = 1e-9
        if abs(lhs.expectedCostPerTask - rhs.expectedCostPerTask) > epsilon {
            return lhs.expectedCostPerTask < rhs.expectedCostPerTask
        }
        let lhsLegs = lhs.route.fallback == nil ? 1 : 2
        let rhsLegs = rhs.route.fallback == nil ? 1 : 2
        if lhsLegs != rhsLegs { return lhsLegs < rhsLegs }
        return lhs.route.description < rhs.route.description
    }
}

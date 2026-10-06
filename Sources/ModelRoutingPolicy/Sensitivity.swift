import Foundation

public enum Sensitivity {
    /// Expected number of tasks per month that end with a human picking them up.
    public static func monthlyEscalations(_ policy: RoutingPolicy, mix: [TaskClass: Int]) -> Double {
        policy.entries.reduce(0) { total, entry in
            total + Double(mix[entry.taskClass] ?? 0) * (1 - entry.economics.agentResolveRate)
        }
    }

    /// The human escalation cost at which two policies cost the same per month.
    /// Below it the policy with lower model spend wins; above it the one with
    /// fewer escalations wins. `nil` if the policies escalate equally often
    /// (then model spend alone decides) or if the break-even would be negative.
    public static func breakEvenEscalationCost(_ a: RoutingPolicy, _ b: RoutingPolicy,
                                               mix: [TaskClass: Int]) -> Double? {
        let spendA = a.monthlyModelSpend(mix: mix)
        let spendB = b.monthlyModelSpend(mix: mix)
        let escA = monthlyEscalations(a, mix: mix)
        let escB = monthlyEscalations(b, mix: mix)
        let escalationGap = escB - escA
        guard abs(escalationGap) > 1e-9 else { return nil }
        let breakEven = (spendA - spendB) / escalationGap
        return breakEven >= 0 ? breakEven : nil
    }
}

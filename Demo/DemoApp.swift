import SwiftUI
import ModelRoutingPolicy

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum DemoTab: String, CaseIterable, Identifiable {
    case policy, release, compare
    var id: String { rawValue }
    var title: String {
        switch self {
        case .policy: return "Policy"
        case .release: return "Release gate"
        case .compare: return "Per token vs per task"
        }
    }
}

private let wholeDollars: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
}()

func dollars(_ value: Double) -> String {
    guard value >= 100 else { return String(format: "$%.2f", value) }
    return "$" + (wholeDollars.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value))
}

func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

/// Launch arguments (used by CI to take screenshots):
///   -tab policy|release|compare
///   -escalation <dollars>   (human cost per failed agent attempt, default 60)
struct RootView: View {
    @State private var tab: DemoTab
    @State private var escalationCost: Double

    init() {
        let raw = UserDefaults.standard.string(forKey: "tab") ?? DemoTab.policy.rawValue
        _tab = State(initialValue: DemoTab(rawValue: raw) ?? .policy)
        let cost = UserDefaults.standard.double(forKey: "escalation")
        _escalationCost = State(initialValue: cost > 0 ? cost : 60)
    }

    var assumptions: Assumptions { Assumptions(humanEscalationCost: escalationCost) }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .policy: PolicyView(assumptions: assumptions)
                case .release: ReleaseView(assumptions: assumptions)
                case .compare: CompareView(assumptions: assumptions)
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    Picker("View", selection: $tab) {
                        ForEach(DemoTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Human cost per escalation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(dollars(escalationCost), value: $escalationCost, in: 5...200, step: 5)
                            .font(.caption.monospacedDigit())
                            .fixedSize()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .navigationTitle("Model routing policy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Policy

struct PolicyView: View {
    let assumptions: Assumptions

    var body: some View {
        let policy = PolicyBuilder.derive(from: SampleTeam.afterRelease, assumptions: assumptions)
        let mix = SampleTeam.monthlyMix
        List {
            Section {
                ForEach(policy.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.taskClass.displayName).font(.headline)
                            Spacer()
                            Text("\(mix[entry.taskClass] ?? 0)/mo")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.route.description)
                            .font(.subheadline)
                            .foregroundStyle(entry.route.primary.model == Catalog.opus55 ? Color.purple : Color.teal)
                        HStack(spacing: 12) {
                            Label(dollars(entry.economics.expectedCostPerTask) + " per task", systemImage: "dollarsign.circle")
                            Label(percent(entry.economics.agentResolveRate) + " agent-resolved", systemImage: "checkmark.seal")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        if entry.belowFloor {
                            Text("No route clears the resolve-rate floor")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Derived from \(policy.suiteLabel) eval suite")
            } footer: {
                Text(verbatim: "Cheapest expected cost per task that keeps ≥\(Int(assumptions.minimumAgentResolveRate * 100))% agent-resolved. Expected cost = model spend + escalation spend + human cost for what still fails. Sample data is constructed, not measured.")
            }

            Section("Monthly at this mix") {
                row("Expected total", dollars(policy.monthlyCost(mix: mix)))
                row("Model spend only", dollars(policy.monthlyModelSpend(mix: mix)))
                row("Escalations to a human", String(format: "%.1f", Sensitivity.monthlyEscalations(policy, mix: mix)))
            }
        }
    }
}

func row(_ title: String, _ value: String) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(value).font(.body.monospacedDigit()).foregroundStyle(.secondary)
    }
}

// MARK: - Release gate

struct ReleaseView: View {
    let assumptions: Assumptions

    var body: some View {
        let report = ReleaseGate.evaluate(current: SampleTeam.beforeRelease,
                                          candidate: SampleTeam.afterRelease,
                                          mix: SampleTeam.monthlyMix,
                                          assumptions: assumptions)
        List {
            Section {
                switch report.verdict {
                case .adopt(let saving):
                    Label("ADOPT · saves \(dollars(saving))/mo", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                case .hold(let regressions):
                    VStack(alignment: .leading, spacing: 4) {
                        Label("HOLD · resolve rate regresses", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(regressions.map(\.displayName).joined(separator: ", "))
                            .font(.subheadline)
                    }
                }
                row("Current policy", dollars(report.currentMonthlyCost) + "/mo")
                row("Candidate policy", dollars(report.candidateMonthlyCost) + "/mo")
            } header: {
                Text("Sonnet 5.5 shipped: re-run the suite")
            }

            Section("Per class") {
                ForEach(report.changes) { change in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(change.taskClass.displayName).font(.headline)
                            Spacer()
                            if change.primaryFlipped {
                                Text("PRIMARY FLIP").font(.caption2.bold()).foregroundStyle(.orange)
                            } else if change.flipped {
                                Text("fallback moved").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text("was  \(change.current?.route.description ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("now  \(change.candidate?.route.description ?? "—")")
                            .font(.caption)
                        Text(String(format: "Δ resolve %+.2f pts · Δ cost %@", change.resolveRateDeltaPoints,
                                    (change.costDelta < 0 ? "−" : "+") + dollars(abs(change.costDelta))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(change.resolveRateDeltaPoints < -2 ? Color.red : Color.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Compare

struct CompareView: View {
    let assumptions: Assumptions

    var body: some View {
        let suite = SampleTeam.afterRelease
        let mix = SampleTeam.monthlyMix
        let allOpus = PolicyBuilder.uniform(SampleTeam.opusHigh, suite: suite, assumptions: assumptions)
        let allSonnet = PolicyBuilder.uniform(SampleTeam.sonnet55Medium, suite: suite, assumptions: assumptions)
        let routed = PolicyBuilder.derive(from: suite, assumptions: assumptions)
        let breakEven = Sensitivity.breakEvenEscalationCost(allOpus, allSonnet, mix: mix)

        List {
            Section {
                strategy("Everything on Opus 5.5 · high", allOpus, mix)
                strategy("Everything on Sonnet 5.5 · medium", allSonnet, mix)
                strategy("Routed by task class", routed, mix)
            } header: {
                Text("Same month, three policies")
            } footer: {
                Text("Sonnet 5.5 is half the price per token. Whether it is cheaper per task depends on how often it fails and what a failure costs your team.")
            }

            Section("Break-even") {
                if let breakEven {
                    Text("All-Sonnet only beats all-Opus if a failed attempt costs a human less than \(dollars(breakEven)).")
                } else {
                    Text("No break-even: the two policies escalate equally often.")
                }
            }
        }
    }

    func strategy(_ title: String, _ policy: RoutingPolicy, _ mix: [TaskClass: Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            HStack {
                VStack(alignment: .leading) {
                    Text("Model spend").font(.caption).foregroundStyle(.secondary)
                    Text(dollars(policy.monthlyModelSpend(mix: mix))).font(.title3.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Escalations").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.0f", Sensitivity.monthlyEscalations(policy, mix: mix))).font(.title3.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Expected total").font(.caption).foregroundStyle(.secondary)
                    Text(dollars(policy.monthlyCost(mix: mix))).font(.title3.bold().monospacedDigit())
                }
            }
        }
        .padding(.vertical, 2)
    }
}

import XCTest
@testable import ModelRoutingPolicy

final class ModelRoutingPolicyTests: XCTestCase {
    let mix = SampleTeam.monthlyMix
    let after = SampleTeam.afterRelease
    let before = SampleTeam.beforeRelease

    // MARK: - Prices and per-row economics

    func testListPricesMatchPricingDocs() {
        XCTAssertEqual(Catalog.opus55.price, ModelPrice(inputPerMTok: 4, outputPerMTok: 20))
        XCTAssertEqual(Catalog.sonnet55.price, ModelPrice(inputPerMTok: 2, outputPerMTok: 10))
    }

    func testSonnetIsHalfThePricePerToken() {
        let opus = Catalog.opus55.price.cost(inputTokens: 1_000_000, outputTokens: 1_000_000)
        let sonnet = Catalog.sonnet55.price.cost(inputTokens: 1_000_000, outputTokens: 1_000_000)
        XCTAssertEqual(sonnet / opus, 0.5, accuracy: 1e-12)
    }

    func testCostPerAttemptAndPerResolved() throws {
        let opusArch = try XCTUnwrap(after.result(for: SampleTeam.opusHigh, .architecturePlanning))
        XCTAssertEqual(opusArch.costPerAttempt, 1.16, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(opusArch.costPerResolved), 1.16 * 20 / 17, accuracy: 1e-9)

        let sonnetArch = try XCTUnwrap(after.result(for: SampleTeam.sonnet55Medium, .architecturePlanning))
        XCTAssertEqual(sonnetArch.costPerAttempt, 0.52, accuracy: 1e-9)
        XCTAssertEqual(sonnetArch.resolveRate, 0.55, accuracy: 1e-12)
    }

    func testCostPerResolvedIsNilWhenNothingResolved() {
        let row = EvalResult(SampleTeam.sonnet5Medium, .architecturePlanning,
                             attempts: 5, resolved: 0, inputTokens: 10_000, outputTokens: 1_000)
        XCTAssertNil(row.costPerResolved)
        XCTAssertEqual(row.resolveRate, 0)
    }

    // MARK: - Route economics

    func testSingleLegRouteChargesHumanForEveryFailure() throws {
        let e = try XCTUnwrap(Economics.price(Route(primary: SampleTeam.sonnet55Medium), for: .architecturePlanning,
                                              in: after, assumptions: Assumptions()))
        XCTAssertEqual(e.expectedModelSpend, 0.52, accuracy: 1e-9)
        XCTAssertEqual(e.expectedHumanCost, 0.45 * 60, accuracy: 1e-9)
    }

    func testFallbackIsDiscountedForHardness() throws {
        let route = Route(primary: SampleTeam.opusHigh, fallback: SampleTeam.sonnet55High)
        let e = try XCTUnwrap(Economics.price(route, for: .architecturePlanning, in: after, assumptions: Assumptions()))
        // Sonnet 5.5 high resolves 65%; on a task Opus already failed we count half of that.
        XCTAssertEqual(e.agentResolveRate, 0.85 + 0.15 * 0.325, accuracy: 1e-9)
        XCTAssertEqual(e.expectedModelSpend, 1.16 + 0.15 * 0.65, accuracy: 1e-9)
    }

    func testUnmeasuredRouteIsNotPriced() {
        let route = Route(primary: SampleTeam.sonnet55Medium)
        XCTAssertNil(Economics.price(route, for: .buildFixLoop, in: before, assumptions: Assumptions()))
    }

    // MARK: - The headline comparison

    func testHalfPriceModelEverywhereCostsMoreOnceFailuresArePriced() {
        let allOpus = PolicyBuilder.uniform(SampleTeam.opusHigh, suite: after)
        let allSonnet = PolicyBuilder.uniform(SampleTeam.sonnet55Medium, suite: after)

        XCTAssertEqual(allOpus.monthlyModelSpend(mix: mix), 553.2, accuracy: 1e-6)
        XCTAssertEqual(allSonnet.monthlyModelSpend(mix: mix), 221.2, accuracy: 1e-6)
        XCTAssertEqual(allOpus.monthlyCost(mix: mix), 5_773.2, accuracy: 1e-6)
        XCTAssertEqual(allSonnet.monthlyCost(mix: mix), 8_081.2, accuracy: 1e-6)

        XCTAssertEqual(Sensitivity.monthlyEscalations(allOpus, mix: mix), 87, accuracy: 1e-9)
        XCTAssertEqual(Sensitivity.monthlyEscalations(allSonnet, mix: mix), 131, accuracy: 1e-9)
    }

    func testBreakEvenEscalationCostIsUnderEightDollars() throws {
        let allOpus = PolicyBuilder.uniform(SampleTeam.opusHigh, suite: after)
        let allSonnet = PolicyBuilder.uniform(SampleTeam.sonnet55Medium, suite: after)
        let breakEven = try XCTUnwrap(Sensitivity.breakEvenEscalationCost(allOpus, allSonnet, mix: mix))
        XCTAssertEqual(breakEven, 332.0 / 44.0, accuracy: 1e-9)   // ≈ $7.55
    }

    func testBreakEvenIsNilWhenEscalationsAreEqual() {
        let p = PolicyBuilder.uniform(SampleTeam.opusHigh, suite: after)
        XCTAssertNil(Sensitivity.breakEvenEscalationCost(p, p, mix: mix))
    }

    // MARK: - Derived policy

    func testDerivedPolicyKeepsJudgmentWorkOnOpus() throws {
        let policy = PolicyBuilder.derive(from: after)
        XCTAssertEqual(policy.entries.count, 5)
        XCTAssertEqual(try XCTUnwrap(policy.entry(for: .architecturePlanning)).route,
                       Route(primary: SampleTeam.opusHigh, fallback: SampleTeam.sonnet55High))
        XCTAssertEqual(try XCTUnwrap(policy.entry(for: .ambiguousRefactor)).route,
                       Route(primary: SampleTeam.opusHigh, fallback: SampleTeam.sonnet55High))
        XCTAssertEqual(try XCTUnwrap(policy.entry(for: .mechanicalMigration)).route,
                       Route(primary: SampleTeam.sonnet55Medium, fallback: SampleTeam.sonnet55High))
        XCTAssertEqual(try XCTUnwrap(policy.entry(for: .buildFixLoop)).route,
                       Route(primary: SampleTeam.sonnet55Medium, fallback: SampleTeam.sonnet55High))
        XCTAssertEqual(try XCTUnwrap(policy.entry(for: .testGeneration)).route,
                       Route(primary: SampleTeam.sonnet55High, fallback: SampleTeam.opusHigh))
        XCTAssertTrue(policy.entries.allSatisfy { !$0.belowFloor })
    }

    func testRoutedPolicyBeatsBothUniformPolicies() {
        let routed = PolicyBuilder.derive(from: after)
        XCTAssertEqual(routed.monthlyCost(mix: mix), 3_214.98, accuracy: 1e-6)
        XCTAssertEqual(routed.monthlyModelSpend(mix: mix), 324.48, accuracy: 1e-6)
        XCTAssertEqual(Sensitivity.monthlyEscalations(routed, mix: mix), 48.175, accuracy: 1e-9)
        XCTAssertLessThan(routed.monthlyCost(mix: mix),
                          PolicyBuilder.uniform(SampleTeam.opusHigh, suite: after).monthlyCost(mix: mix))
    }

    func testFloorFallsBackToBestResolveRateAndFlagsIt() throws {
        let strict = Assumptions(minimumAgentResolveRate: 0.999)
        let policy = PolicyBuilder.derive(from: after, assumptions: strict)
        let arch = try XCTUnwrap(policy.entry(for: .architecturePlanning))
        XCTAssertTrue(arch.belowFloor)
    }

    // MARK: - Release gate

    func testReleaseGateAdoptsOnEvidence() {
        let report = ReleaseGate.evaluate(current: before, candidate: after, mix: mix)
        XCTAssertEqual(report.currentMonthlyCost, 3_824.14, accuracy: 1e-6)
        XCTAssertEqual(report.candidateMonthlyCost, 3_214.98, accuracy: 1e-6)
        guard case .adopt(let saving) = report.verdict else { return XCTFail("expected adopt") }
        XCTAssertEqual(saving, 609.16, accuracy: 1e-6)

        let primaryFlips = report.changes.filter(\.primaryFlipped).map(\.taskClass)
        XCTAssertEqual(primaryFlips, [.mechanicalMigration, .buildFixLoop, .testGeneration])
        XCTAssertEqual(report.flippedClasses.count, 5)   // every fallback moved off Sonnet 5
    }

    func testReleaseGateHoldsWhenCheapAssumptionTradesAwayResolveRate() {
        let cheapHumans = Assumptions(humanEscalationCost: 5)
        let report = ReleaseGate.evaluate(current: before, candidate: after, mix: mix, assumptions: cheapHumans)
        XCTAssertEqual(report.verdict, .hold(regressions: [.ambiguousRefactor]))
        let refactor = report.changes.first { $0.taskClass == .ambiguousRefactor }
        XCTAssertEqual(refactor?.resolveRateDeltaPoints ?? 0, -2.375, accuracy: 1e-9)
    }

    func testPolicyIsStableAcrossAWideRangeOfEscalationCosts() {
        let reference = PolicyBuilder.derive(from: after).entries.map(\.route)
        for cost in [15.0, 30, 60, 120] {
            let routes = PolicyBuilder.derive(from: after, assumptions: Assumptions(humanEscalationCost: cost))
                .entries.map(\.route)
            XCTAssertEqual(routes, reference, "policy changed at $\(cost) per escalation")
        }
    }

    func testFallbackDiscountIsClamped() {
        XCTAssertEqual(Assumptions(fallbackHardnessDiscount: 3).fallbackHardnessDiscount, 1)
        XCTAssertEqual(Assumptions(fallbackHardnessDiscount: -1).fallbackHardnessDiscount, 0)
    }

    func testEffortOrdering() {
        XCTAssertLessThan(Effort.low, Effort.medium)
        XCTAssertLessThan(Effort.medium, Effort.high)
    }
}

import Foundation

/// Constructed sample data for the demo. These are NOT benchmark results and not
/// measurements of any real team: they are illustrative eval rows shaped like the
/// suite a team would run (20 real tasks per class), so every number in the
/// article can be recomputed from this file. Replace them with your own runs.
public enum SampleTeam {
    public static let opusHigh = ModelChoice(Catalog.opus55, .high)
    public static let sonnet55Medium = ModelChoice(Catalog.sonnet55, .medium)
    public static let sonnet55High = ModelChoice(Catalog.sonnet55, .high)
    public static let sonnet5Medium = ModelChoice(Catalog.sonnet5, .medium)

    /// Tasks per month the team hands to its agent, by class.
    public static let monthlyMix: [TaskClass: Int] = [
        .architecturePlanning: 40,
        .ambiguousRefactor: 80,
        .mechanicalMigration: 300,
        .buildFixLoop: 600,
        .testGeneration: 400
    ]

    private static func row(_ c: ModelChoice, _ t: TaskClass, _ resolved: Int,
                            _ input: Int, _ output: Int) -> EvalResult {
        EvalResult(c, t, attempts: 20, resolved: resolved, inputTokens: input, outputTokens: output)
    }

    static let opusRows: [EvalResult] = [
        row(opusHigh, .architecturePlanning, 17, 180_000, 22_000),
        row(opusHigh, .ambiguousRefactor,    16, 150_000, 18_000),
        row(opusHigh, .mechanicalMigration,  19,  60_000,  9_000),
        row(opusHigh, .buildFixLoop,         19,  40_000,  4_000),
        row(opusHigh, .testGeneration,       19,  50_000, 10_000)
    ]

    static let sonnet5Rows: [EvalResult] = [
        row(sonnet5Medium, .architecturePlanning,  9, 200_000, 22_000),
        row(sonnet5Medium, .ambiguousRefactor,    11, 170_000, 18_000),
        row(sonnet5Medium, .mechanicalMigration,  17,  60_000,  9_000),
        row(sonnet5Medium, .buildFixLoop,         17,  45_000,  4_500),
        row(sonnet5Medium, .testGeneration,       16,  55_000, 10_000)
    ]

    static let sonnet55Rows: [EvalResult] = [
        row(sonnet55Medium, .architecturePlanning, 11, 170_000, 18_000),
        row(sonnet55Medium, .ambiguousRefactor,    13, 140_000, 15_000),
        row(sonnet55Medium, .mechanicalMigration,  19,  45_000,  7_000),
        row(sonnet55Medium, .buildFixLoop,         19,  30_000,  3_000),
        row(sonnet55Medium, .testGeneration,       18,  40_000,  8_000),
        row(sonnet55High,   .architecturePlanning, 13, 200_000, 25_000),
        row(sonnet55High,   .ambiguousRefactor,    15, 170_000, 20_000),
        row(sonnet55High,   .mechanicalMigration,  19,  55_000,  8_000),
        row(sonnet55High,   .buildFixLoop,         19,  34_000,  3_500),
        row(sonnet55High,   .testGeneration,       19,  46_000,  9_000)
    ]

    /// The suite as it stood before Sonnet 5.5 shipped.
    public static let beforeRelease = EvalSuite(label: "Before Sonnet 5.5",
                                                results: opusRows + sonnet5Rows)
    /// The same suite re-run on release day, with Sonnet 5.5 added.
    public static let afterRelease = EvalSuite(label: "After Sonnet 5.5",
                                               results: opusRows + sonnet5Rows + sonnet55Rows)
}

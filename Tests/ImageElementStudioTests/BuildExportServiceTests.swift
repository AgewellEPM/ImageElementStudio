import XCTest
@testable import ImageElementStudio

@MainActor
final class BuildExportServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> BuildExportService {
        BuildExportService()
    }

    // MARK: - slugified()

    func testSlugifiedConvertsSpacesToDashes() {
        let service = makeService()
        XCTAssertEqual(service.slugified("My Project"), "my-project")
    }

    func testSlugifiedLowercasesInput() {
        let service = makeService()
        XCTAssertEqual(service.slugified("HelloWorld"), "helloworld")
    }

    func testSlugifiedStripsSpecialCharacters() {
        let service = makeService()
        XCTAssertEqual(service.slugified("App! @v2.0"), "app-v2-0")
    }

    func testSlugifiedCollapsesConsecutiveDashes() {
        let service = makeService()
        // Multiple spaces/special chars should produce single dashes
        XCTAssertEqual(service.slugified("Hello   World"), "hello-world")
    }

    func testSlugifiedTrimsLeadingAndTrailingDashes() {
        let service = makeService()
        XCTAssertEqual(service.slugified(" - Leading - "), "leading")
    }

    func testSlugifiedReturnsProjectForEmptyString() {
        let service = makeService()
        XCTAssertEqual(service.slugified(""), "project")
    }

    func testSlugifiedReturnsProjectForAllSpecialChars() {
        let service = makeService()
        XCTAssertEqual(service.slugified("!@#$%"), "project")
    }

    // MARK: - uniqueStrings()

    func testUniqueStringsRemovesDuplicates() {
        let service = makeService()
        let result = service.uniqueStrings(["a", "b", "a", "c", "b"])
        XCTAssertEqual(result, ["a", "b", "c"])
    }

    func testUniqueStringsPreservesOrder() {
        let service = makeService()
        let result = service.uniqueStrings(["c", "b", "a"])
        XCTAssertEqual(result, ["c", "b", "a"])
    }

    func testUniqueStringsTrimsWhitespace() {
        let service = makeService()
        let result = service.uniqueStrings(["  hello ", "hello", " hello"])
        XCTAssertEqual(result, ["hello"])
    }

    func testUniqueStringsRemovesEmptyStrings() {
        let service = makeService()
        let result = service.uniqueStrings(["a", "", "  ", "b"])
        XCTAssertEqual(result, ["a", "b"])
    }

    func testUniqueStringsEmptyInput() {
        let service = makeService()
        let result = service.uniqueStrings([])
        XCTAssertEqual(result, [])
    }

    // MARK: - makeQualityGateSummary

    func testQualityGateSummaryPassStatusAbove85() {
        let service = makeService()
        // Include both regular and full-app smoke checks so all rates are 1.0
        var smokeChecks = (0..<5).map { i in
            SmokeCheckResult(
                id: UUID(), name: "Check \(i)", target: "web",
                command: "test", passed: true, output: "ok"
            )
        }
        smokeChecks += (0..<5).map { i in
            SmokeCheckResult(
                id: UUID(), name: "Full app check \(i)", target: "web",
                command: "test", passed: true, output: "ok"
            )
        }
        // Include a low-impact diff entry so diffHealthScore is near 1.0 instead of default 0.5
        let diffs = [
            DesignCodeDiffEntry(
                id: UUID(), category: "layout", title: "Minor",
                detail: "Minor diff", impactScore: 0.05
            ),
        ]
        let summary = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: smokeChecks,
            diffEntries: diffs,
            benchmarkPassRate: 1.0,
            reviewGatePassed: true,
            overdueCommentCount: 0,
            reviewGateBlockReason: nil
        )
        // smokePassRate=1.0 -> 30, fullAppPassRate=1.0 -> 15, diffHealth~0.95 -> 19, benchmark=20, review=15 => ~99
        XCTAssertEqual(summary.status, .pass)
        XCTAssertGreaterThanOrEqual(summary.overallScore, 85)
    }

    func testQualityGateSummaryFailStatusBelowThreshold() {
        let service = makeService()
        // No smoke checks, no benchmark, review not passed
        let summary = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: [],
            diffEntries: [],
            benchmarkPassRate: 0.0,
            reviewGatePassed: false,
            overdueCommentCount: 5,
            reviewGateBlockReason: "Not approved"
        )
        XCTAssertEqual(summary.status, .fail)
        XCTAssertLessThan(summary.overallScore, 65)
    }

    func testQualityGateSummaryWarningStatusBetweenThresholds() {
        let service = makeService()
        // Create a mix that lands between 65 and 85
        let smokeChecks = (0..<10).map { i in
            SmokeCheckResult(
                id: UUID(), name: "Check \(i)", target: "web",
                command: "test", passed: i < 9, output: "ok"
            )
        }
        let summary = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: smokeChecks,
            diffEntries: [],
            benchmarkPassRate: 0.9,
            reviewGatePassed: true,
            overdueCommentCount: 0,
            reviewGateBlockReason: nil
        )
        // smokePassRate = 0.9 -> 27 pts, fullApp = 0.5 (none) -> 7.5 pts,
        // diffHealth = 0.5 (none) -> 10 pts, benchmark = 0.9 -> 18 pts, review = 15 pts
        // Total = 77.5 -> warning
        XCTAssertEqual(summary.status, .warning)
    }

    func testQualityGateSummaryBlockingIssuesForLowSmoke() {
        let service = makeService()
        let smokeChecks = (0..<10).map { i in
            SmokeCheckResult(
                id: UUID(), name: "Check \(i)", target: "web",
                command: "test", passed: i < 5, output: "ok"
            )
        }
        let summary = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: smokeChecks,
            diffEntries: [],
            benchmarkPassRate: 1.0,
            reviewGatePassed: true,
            overdueCommentCount: 0,
            reviewGateBlockReason: nil
        )
        XCTAssertTrue(summary.blockingIssues.contains("Smoke-check pass rate below 90%."))
    }

    func testQualityGateSummaryBlockingIssuesForUnpassedReview() {
        let service = makeService()
        let summary = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: [],
            diffEntries: [],
            benchmarkPassRate: 1.0,
            reviewGatePassed: false,
            overdueCommentCount: 0,
            reviewGateBlockReason: "Approval required"
        )
        XCTAssertTrue(summary.blockingIssues.contains("Approval required"))
    }

    func testQualityGateSummaryOverduePenalty() {
        let service = makeService()
        let smokeChecks = (0..<10).map { i in
            SmokeCheckResult(
                id: UUID(), name: "Check \(i)", target: "web",
                command: "test", passed: true, output: "ok"
            )
        }
        let summaryNoOverdue = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: smokeChecks,
            diffEntries: [],
            benchmarkPassRate: 1.0,
            reviewGatePassed: true,
            overdueCommentCount: 0,
            reviewGateBlockReason: nil
        )
        let summaryWithOverdue = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: smokeChecks,
            diffEntries: [],
            benchmarkPassRate: 1.0,
            reviewGatePassed: true,
            overdueCommentCount: 3,
            reviewGateBlockReason: nil
        )
        XCTAssertGreaterThan(summaryNoOverdue.overallScore, summaryWithOverdue.overallScore)
    }

    func testQualityGateSummaryHighImpactDiffIssue() {
        let service = makeService()
        let diffs = [
            DesignCodeDiffEntry(
                id: UUID(), category: "layout", title: "Drift",
                detail: "Major drift", impactScore: 0.8
            ),
        ]
        let summary = service.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: [],
            diffEntries: diffs,
            benchmarkPassRate: 1.0,
            reviewGatePassed: true,
            overdueCommentCount: 0,
            reviewGateBlockReason: nil
        )
        XCTAssertTrue(summary.blockingIssues.contains("High-impact design/code drifts detected."))
    }

    // MARK: - buildConfirmationLines

    func testBuildConfirmationLinesContainsTargetAndProject() {
        let service = makeService()
        let context = makeMinimalBuildContext(projectName: "ConfTest")
        let lines = service.buildConfirmationLines(for: .web, context: context)

        XCTAssertTrue(lines.contains { $0.contains("Web") })
        XCTAssertTrue(lines.contains { $0.contains("ConfTest") })
    }

    func testBuildConfirmationLinesReportsNoActiveArtboard() {
        let service = makeService()
        var context = makeMinimalBuildContext()
        context.activeArtboard = nil
        let lines = service.buildConfirmationLines(for: .ios, context: context)

        XCTAssertTrue(lines.contains { $0.contains("No active artboard") })
    }

    func testBuildConfirmationLinesReportsReviewGateReady() {
        let service = makeService()
        var context = makeMinimalBuildContext()
        context.canExportBuildArtifacts = true
        let lines = service.buildConfirmationLines(for: .macos, context: context)

        XCTAssertTrue(lines.contains { $0.contains("Ready") })
    }

    func testBuildConfirmationLinesReportsReviewGateBlocked() {
        let service = makeService()
        var context = makeMinimalBuildContext()
        context.canExportBuildArtifacts = false
        let lines = service.buildConfirmationLines(for: .macos, context: context)

        XCTAssertTrue(lines.contains { $0.contains("Blocked") })
    }

    // MARK: - deterministicManifestSnapshot

    func testDeterministicManifestSnapshotIsConsistentAcrossCalls() {
        let service = makeService()
        let context = makeMinimalBuildContext()
        let snapshot1 = service.deterministicManifestSnapshot(for: .web, context: context)
        let snapshot2 = service.deterministicManifestSnapshot(for: .web, context: context)

        XCTAssertEqual(snapshot1, snapshot2)
    }

    func testDeterministicManifestSnapshotDiffersPerTarget() {
        let service = makeService()
        let context = makeMinimalBuildContext()
        let webSnapshot = service.deterministicManifestSnapshot(for: .web, context: context)
        let iosSnapshot = service.deterministicManifestSnapshot(for: .ios, context: context)

        XCTAssertNotEqual(webSnapshot.target, iosSnapshot.target)
    }

    // MARK: - Helpers

    private func makeMinimalBuildContext(projectName: String = "TestProject") -> BuildExportService.BuildContext {
        let artboard = Artboard.empty(named: "Main", width: 1280, height: 720)
        let doc = AnalysisDocument(
            image: ImageDescriptor(filename: "test.png", width: 1280, height: 720),
            artboard: artboard,
            metadata: AnalysisMetadata(generatedAt: Date(timeIntervalSince1970: 0), engine: "test", notes: []),
            scope: nil,
            blueprint: nil
        )
        return BuildExportService.BuildContext(
            projectName: projectName,
            projectID: "test-id",
            pipelineMode: .auto,
            mockupStylePreset: .apple_hig,
            artboards: [artboard],
            latestScope: nil,
            latestBlueprint: nil,
            latestDesignTokens: nil,
            tokenRevisions: [],
            latestComponentSpecs: [],
            componentInstances: [],
            acceptedStrategySpec: nil,
            importLossReport: nil,
            reviewComments: [],
            reviewApprovalState: "approved",
            latestBenchmarkReport: nil,
            benchmarkHistory: [],
            benchmarkTrendScore: nil,
            designCodeDiffs: [],
            latestBuildQualityReport: nil,
            canExportBuildArtifacts: true,
            reviewGateBlockReason: nil,
            reviewGateStatusLine: "Approved",
            overdueReviewCommentCount: 0,
            unresolvedReviewCommentCount: 0,
            qualityGateScoreLine: "Score: 90",
            memorySnapshotCount: 0,
            memoryEntryCount: 0,
            activeArtboard: artboard,
            document: doc,
            strategySessionStage: nil,
            acceptedStrategySpecConfidence: nil
        )
    }
}

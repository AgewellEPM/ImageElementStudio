import XCTest
@testable import ImageElementStudio

@MainActor
final class StudioSnapshotTests: XCTestCase {
    func testManifestSnapshotMatchesExpectedFixture() {
        let viewModel = makeSnapshotViewModel()

        let snapshot = viewModel.deterministicManifestSnapshot(for: .ios)

        XCTAssertEqual(
            snapshot,
            StudioViewModel.DeterministicManifestSnapshot(
                schemaVersion: 4,
                target: "ios",
                projectName: "Snapshot Lab",
                projectID: "snapshot-lab",
                pipelineMode: "guided",
                stylePreset: "apple_hig",
                activeArtboardName: "Main",
                elementCount: 3,
                inferredControls: ["Export"],
                inferredStates: ["Review Ready"],
                componentSpecs: ["PrimaryButton"],
                tokenColorKeys: ["accent.primary", "surface.base"],
                reviewApprovalState: "approved",
                benchmarkPassed: false,
                benchmarkStepPassRate: 0.5,
                benchmarkMedianStepLatencyMilliseconds: 50,
                benchmarkTrendPassRate: 0.75,
                benchmarkTrendMedianStepLatencyMilliseconds: 30
            )
        )
    }

    func testReviewCommentAssigneeDueDateAndOverdueDetection() {
        let viewModel = StudioViewModel()
        viewModel.reviewCommentDraft = "Fix CTA alignment."
        viewModel.reviewCommentAssigneeDraft = "Alex"
        viewModel.reviewCommentHasDueDate = true
        viewModel.reviewCommentDueDateDraft = Date(timeIntervalSince1970: 0)

        viewModel.addReviewComment(viewModel.reviewCommentDraft)

        guard let comment = viewModel.reviewComments.first else {
            XCTFail("Expected comment to be created")
            return
        }
        XCTAssertEqual(comment.assignee, "Alex")
        XCTAssertNotNil(comment.dueDate)
        XCTAssertEqual(viewModel.overdueReviewCommentCount, 1)
        XCTAssertEqual(viewModel.reviewCommentAssigneeDraft, "")
        XCTAssertFalse(viewModel.reviewCommentHasDueDate)
    }

    func testQualityGateSummaryCombinesSignals() {
        let viewModel = StudioViewModel()
        let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let smokeID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let diffID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let benchmarkStepID = UUID(uuidString: "00000000-0000-0000-0000-000000000304")!

        viewModel.reviewComments = [
            DesignReviewComment(
                id: commentID,
                createdAt: Date(timeIntervalSince1970: 1),
                author: "QA",
                assignee: "Dev A",
                dueDate: Date(timeIntervalSince1970: 0),
                message: "Fix failing export path.",
                artboardID: nil,
                elementID: nil,
                resolved: false
            ),
        ]
        viewModel.reviewApprovalState = .changesRequested
        viewModel.designCodeDiffs = [
            DesignCodeDiffEntry(
                id: diffID,
                category: "state",
                title: "Major drift",
                detail: "Critical inferred state missing.",
                impactScore: 1.0
            ),
        ]
        viewModel.latestBenchmarkReport = BenchmarkRunReport(
            generatedAt: Date(timeIntervalSince1970: 10),
            scenario: "Pro Editing Core",
            passed: false,
            steps: [
                BenchmarkStepResult(
                    id: benchmarkStepID,
                    title: "Rotate Handles",
                    passed: false,
                    detail: "Failed",
                    latencyMilliseconds: 25
                ),
            ]
        )
        viewModel.benchmarkHistory = [viewModel.latestBenchmarkReport!]
        viewModel.latestBuildQualityReport = BuildQualityReport(
            generatedAt: Date(timeIntervalSince1970: 20),
            deterministicHash: "abc",
            smokeChecks: [
                SmokeCheckResult(
                    id: smokeID,
                    target: "macos",
                    command: "swift build",
                    passed: false,
                    output: "failed"
                ),
            ],
            passRate: 0,
            diffs: viewModel.designCodeDiffs
        )

        let summary = viewModel.currentQualityGateSummary
        XCTAssertEqual(summary.reviewGatePassed, false)
        XCTAssertEqual(summary.overdueCommentCount, 1)
        XCTAssertEqual(summary.status, .fail)
        XCTAssertLessThan(summary.overallScore, 40)
        XCTAssertTrue(
            summary.blockingIssues.contains(where: { issue in
                issue.localizedCaseInsensitiveContains("review gate") ||
                    issue.localizedCaseInsensitiveContains("approval must be set")
            })
        )
    }

    func testDeterministicAppSpecSnapshotMatchesExpectedFixture() {
        let viewModel = makeSnapshotViewModel()

        let snapshot = viewModel.deterministicAppSpecSnapshot(for: .web)

        XCTAssertEqual(
            snapshot,
            StudioViewModel.DeterministicAppSpecSnapshot(
                target: "web",
                initialState: "Review Ready",
                states: ["Review Ready"],
                controls: ["Export"],
                capabilities: ["Export data", "Inspect metrics"],
                screens: ["Review Ready Screen:Review Ready"],
                transitions: ["Export:Review Ready->Review Ready"]
            )
        )
    }

    func testDiffSnapshotMatchesExpectedFixture() {
        let viewModel = makeSnapshotViewModel()
        let scaffoldContent = "<html><body><h1>Generated Dashboard</h1></body></html>"

        let snapshot = viewModel.deterministicDiffSnapshot(for: .web, scaffoldContent: scaffoldContent)

        XCTAssertEqual(
            snapshot,
            StudioViewModel.DeterministicDiffSnapshot(
                target: "web",
                entries: [
                    .init(
                        category: "state",
                        title: "Missing inferred state in scaffold",
                        detail: "State 'Review Ready' was inferred from design but not emitted into full-app/web/index.html.",
                        impactScore: 0.72
                    ),
                    .init(
                        category: "control",
                        title: "Missing inferred control label in scaffold",
                        detail: "Control 'Export' is not represented in full-app/web/index.html.",
                        impactScore: 0.55
                    ),
                    .init(
                        category: "component",
                        title: "Component metadata not reflected in scaffold",
                        detail: "Generated file lacks explicit component references despite 1 inferred component specs.",
                        impactScore: 0.63
                    ),
                    .init(
                        category: "tokens",
                        title: "Token set not explicitly mapped",
                        detail: "Detected 2 color tokens but scaffold file has no token mapping markers.",
                        impactScore: 0.49
                    ),
                ]
            )
        )
    }

    func testReviewGateRequiresApprovalAndResolvedComments() {
        let viewModel = StudioViewModel()
        let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

        viewModel.reviewComments = [
            DesignReviewComment(
                id: commentID,
                createdAt: Date(timeIntervalSince1970: 100),
                author: "QA",
                message: "Needs spacing fix.",
                artboardID: nil,
                elementID: nil,
                resolved: false
            ),
        ]
        viewModel.reviewApprovalState = .pending

        XCTAssertFalse(viewModel.canExportBuildArtifacts)
        XCTAssertEqual(viewModel.reviewGateBlockReason, "Approval must be set to Approved.")

        XCTAssertFalse(viewModel.setReviewApprovalState(.approved))
        XCTAssertEqual(viewModel.reviewApprovalState, .changesRequested)
        XCTAssertFalse(viewModel.canExportBuildArtifacts)

        viewModel.toggleReviewCommentResolution(commentID)
        XCTAssertEqual(viewModel.unresolvedReviewCommentCount, 0)

        XCTAssertTrue(viewModel.setReviewApprovalState(.approved))
        XCTAssertTrue(viewModel.canExportBuildArtifacts)
        XCTAssertNil(viewModel.reviewGateBlockReason)
    }

    func testFullStackSummaryStatusLinesReflectFailures() {
        let viewModel = StudioViewModel()
        viewModel.latestFullStackBuildSummary = FullStackBuildSummary(
            runID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            generatedAt: Date(timeIntervalSince1970: 1000),
            projectName: "Snapshot Lab",
            projectID: "snapshot-lab",
            reviewGatePassed: true,
            aggregateScore: 74,
            allTargetsPassed: false,
            targetResults: [
                FullStackTargetResult(
                    target: "web",
                    outputPath: "/tmp/web",
                    deterministicHash: "hash-web",
                    smokePassCount: 8,
                    smokeTotalCount: 8,
                    smokePassRate: 1,
                    fullAppPassRate: 1,
                    qualityScore: 91,
                    passed: true,
                    blockingIssues: []
                ),
                FullStackTargetResult(
                    target: "ios",
                    outputPath: "/tmp/ios",
                    deterministicHash: "hash-ios",
                    smokePassCount: 5,
                    smokeTotalCount: 8,
                    smokePassRate: 0.625,
                    fullAppPassRate: 0.5,
                    qualityScore: 57,
                    passed: false,
                    blockingIssues: ["Full-app smoke-check pass rate below 90%."]
                ),
            ],
            blockingIssues: ["Targets failing quality checks: ios."]
        )

        XCTAssertEqual(viewModel.fullStackTargetStatusLines.count, 2)
        XCTAssertTrue(viewModel.fullStackTargetStatusLines.contains(where: { $0.hasPrefix("FAIL IOS:") }))
        XCTAssertTrue(viewModel.fullStackStatusLine.contains("fail"))
        XCTAssertEqual(viewModel.fullStackIssuePreview.first, "Targets failing quality checks: ios.")
    }

    func testEnterpriseReadinessStatusLineReflectsReport() {
        let viewModel = StudioViewModel()
        viewModel.latestEnterpriseReadinessReport = EnterpriseReadinessReport(
            runID: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
            generatedAt: Date(timeIntervalSince1970: 1200),
            projectName: "Snapshot Lab",
            projectID: "snapshot-lab",
            status: .warning,
            score: 72,
            checks: [
                EnterpriseReadinessCheck(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
                    name: "Review approval gate passed",
                    weight: 15,
                    passed: false,
                    detail: "Approval must be set to Approved."
                ),
            ],
            blockers: ["Review approval gate passed: Approval must be set to Approved."],
            recommendedActions: ["Set review to Approved and resolve all open comments."]
        )

        XCTAssertTrue(viewModel.enterpriseReadinessStatusLine.contains("Warning"))
        XCTAssertTrue(viewModel.enterpriseReadinessStatusLine.contains("72"))
        XCTAssertEqual(viewModel.enterpriseReadinessIssuePreview.first, "Review approval gate passed: Approval must be set to Approved.")
        XCTAssertEqual(viewModel.enterpriseReadinessCheckLines.count, 1)
        XCTAssertTrue(viewModel.enterpriseReadinessCheckLines[0].hasPrefix("FAIL"))
    }

    private func makeSnapshotViewModel() -> StudioViewModel {
        let viewModel = StudioViewModel()
        viewModel.projectName = "Snapshot Lab"
        viewModel.memory.projectID = "snapshot-lab"
        viewModel.pipelineMode = .guided
        viewModel.mockupStylePreset = .apple_hig

        let artboardID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!
        let rootID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let headingID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let buttonID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let componentID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let controlID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        let stateID = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
        let runOneStepOneID = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
        let runOneStepTwoID = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
        let runTwoStepOneID = UUID(uuidString: "00000000-0000-0000-0000-000000000109")!
        let runTwoStepTwoID = UUID(uuidString: "00000000-0000-0000-0000-00000000010A")!

        let root = CanvasElement(
            id: rootID,
            name: "Canvas Root",
            kind: .imageRoot,
            frame: ElementFrame(x: 0, y: 0, width: 1440, height: 900),
            confidence: 1.0,
            content: "snapshot.png",
            tags: ["root", "canvas"],
            semanticRole: .unknown,
            semanticReason: "Canvas bounds"
        )
        let heading = CanvasElement(
            id: headingID,
            name: "Header",
            kind: .text,
            frame: ElementFrame(x: 72, y: 48, width: 420, height: 60),
            confidence: 0.94,
            content: "Snapshot Dashboard",
            tags: ["heading"],
            semanticRole: .heading,
            semanticReason: "Primary title"
        )
        let button = CanvasElement(
            id: buttonID,
            name: "Export Button",
            kind: .shape,
            frame: ElementFrame(x: 1120, y: 56, width: 200, height: 56),
            confidence: 0.93,
            content: "Export",
            tags: ["button", "primary"],
            semanticRole: .buttonPrimary,
            semanticReason: "Primary action"
        )

        viewModel.artboards = [
            Artboard(
                id: artboardID,
                name: "Main",
                width: 1440,
                height: 900,
                elements: [root, heading, button]
            ),
        ]
        viewModel.selectedArtboardID = artboardID

        viewModel.latestScope = ProductScopeSnapshot(
            appType: "Analytics Dashboard",
            confidence: 0.91,
            productIntent: "Operational export and review",
            targetUsers: ["Ops", "PM"],
            keyCapabilities: ["Export data", "Inspect metrics"],
            openQuestions: ["Retention baseline?"],
            implementationRoadmap: ["Define export policies", "Instrument key events"],
            summary: "Dashboard focused on metric review and export."
        )

        viewModel.latestBlueprint = BuildBlueprint(
            mirrorScore: 0.88,
            detectionSummary: "Detected primary export flow.",
            controls: [
                InferredControl(
                    id: controlID,
                    name: "export_action",
                    label: "Export",
                    kind: .button,
                    role: .buttonPrimary,
                    sourceElementID: buttonID,
                    frame: button.frame,
                    confidence: 0.9,
                    rationale: "Primary CTA"
                ),
            ],
            states: [
                InferredState(
                    id: stateID,
                    name: "Review Ready",
                    triggerControlID: controlID,
                    triggerLabel: "Export",
                    description: "Review details before exporting.",
                    confidence: 0.86
                ),
            ],
            suggestedArtboards: [],
            buildNotes: ["Keep export as primary action."]
        )

        viewModel.latestDesignTokens = DesignTokenSet(
            colors: [
                "accent.primary": "#2F6BFF",
                "surface.base": "#F8FAFF",
            ],
            typography: [:],
            spacing: [:],
            radius: [:],
            shadow: [:],
            motion: [:]
        )

        viewModel.latestComponentSpecs = [
            ComponentSpec(
                id: componentID,
                name: "PrimaryButton",
                kind: .cta,
                role: .buttonPrimary,
                elementIDs: [buttonID],
                notes: "Shared primary action"
            ),
        ]

        viewModel.reviewComments = [
            DesignReviewComment(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000010B")!,
                createdAt: Date(timeIntervalSince1970: 1),
                author: "Design",
                message: "Looks ready.",
                artboardID: artboardID,
                elementID: buttonID,
                resolved: true
            ),
        ]
        viewModel.reviewApprovalState = .approved

        let runOne = BenchmarkRunReport(
            generatedAt: Date(timeIntervalSince1970: 10),
            scenario: "Pro Editing Core",
            passed: true,
            steps: [
                BenchmarkStepResult(
                    id: runOneStepOneID,
                    title: "Multi-select",
                    passed: true,
                    detail: "Selected 3 elements.",
                    latencyMilliseconds: 10
                ),
                BenchmarkStepResult(
                    id: runOneStepTwoID,
                    title: "Distribute",
                    passed: true,
                    detail: "Distributed selection.",
                    latencyMilliseconds: 20
                ),
            ]
        )

        let runTwo = BenchmarkRunReport(
            generatedAt: Date(timeIntervalSince1970: 20),
            scenario: "Pro Editing Core",
            passed: false,
            steps: [
                BenchmarkStepResult(
                    id: runTwoStepOneID,
                    title: "Constraint Pins",
                    passed: true,
                    detail: "Pinned left/top.",
                    latencyMilliseconds: 40
                ),
                BenchmarkStepResult(
                    id: runTwoStepTwoID,
                    title: "Rotate Handles",
                    passed: false,
                    detail: "Rotation failed.",
                    latencyMilliseconds: 60
                ),
            ]
        )

        viewModel.latestBenchmarkReport = runTwo
        viewModel.benchmarkHistory = [runOne, runTwo]

        return viewModel
    }
}

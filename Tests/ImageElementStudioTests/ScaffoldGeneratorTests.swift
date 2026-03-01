import XCTest
@testable import ImageElementStudio

final class ScaffoldGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private func makeManifest(
        inferredControls: [InferredControl] = [],
        inferredStates: [InferredState] = [],
        componentSpecs: [ComponentSpec] = [],
        designTokens: DesignTokenSet? = nil,
        capabilities: [String] = []
    ) -> StudioViewModel.BuildManifest {
        let artboardID = UUID(uuidString: "00000000-0000-0000-0000-000000000800")!
        let rootID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!

        let root = CanvasElement(
            id: rootID,
            name: "Root",
            kind: .imageRoot,
            frame: ElementFrame(x: 0, y: 0, width: 1024, height: 768),
            confidence: 1.0,
            content: nil,
            tags: [],
            semanticRole: .unknown,
            semanticReason: "root"
        )

        let artboard = Artboard(id: artboardID, name: "Main", width: 1024, height: 768, elements: [root])

        return StudioViewModel.BuildManifest(
            schemaVersion: 4,
            projectName: "TestProject",
            projectID: "test-project",
            target: "web",
            generatedAt: Date(timeIntervalSince1970: 1000),
            deterministicHash: "abc123",
            appType: "Dashboard",
            productIntent: "Analytics platform",
            capabilities: capabilities,
            mirrorScore: 0.88,
            inferredControls: inferredControls,
            inferredStates: inferredStates,
            suggestedStateArtboards: [],
            designTokens: designTokens,
            tokenRevisions: [],
            componentSpecs: componentSpecs,
            componentInstances: [],
            strategySpec: nil,
            importLossReport: nil,
            reviewComments: [],
            reviewApprovalState: "approved",
            benchmarkReport: nil,
            benchmarkHistoryCount: 0,
            benchmarkTrendScore: nil,
            pipelineMode: "guided",
            stylePreset: "apple_hig",
            activeArtboardName: "Main",
            artboardCount: 1,
            elementCount: 1,
            memorySnapshotCount: 0,
            analysisDocument: AnalysisDocument(
                image: ImageDescriptor(filename: "test.png", width: 1024, height: 768),
                artboard: artboard,
                metadata: AnalysisMetadata(generatedAt: Date(timeIntervalSince1970: 1000), engine: "test", notes: []),
                scope: nil,
                blueprint: nil
            )
        )
    }

    // MARK: - deterministicUUID consistency

    func testDeterministicUUIDReturnsSameValueForSameSeed() {
        let uuid1 = ScaffoldGenerator.deterministicUUID(seed: "test-seed-alpha")
        let uuid2 = ScaffoldGenerator.deterministicUUID(seed: "test-seed-alpha")

        XCTAssertEqual(uuid1, uuid2)
    }

    func testDeterministicUUIDReturnsDifferentValuesForDifferentSeeds() {
        let uuid1 = ScaffoldGenerator.deterministicUUID(seed: "seed-a")
        let uuid2 = ScaffoldGenerator.deterministicUUID(seed: "seed-b")

        XCTAssertNotEqual(uuid1, uuid2)
    }

    func testDeterministicUUIDProducesValidVersion4UUID() {
        let uuid = ScaffoldGenerator.deterministicUUID(seed: "version-check")
        let uuidString = uuid.uuidString

        // Version 4 UUID has specific format: xxxxxxxx-xxxx-4xxx-{8,9,a,b}xxx-xxxxxxxxxxxx
        let parts = uuidString.split(separator: "-")
        XCTAssertEqual(parts.count, 5)
        // Third segment starts with "4"
        XCTAssertTrue(parts[2].hasPrefix("4"))
        // Fourth segment starts with 8, 9, A, or B
        let validPrefixes: [Character] = ["8", "9", "A", "B"]
        XCTAssertTrue(validPrefixes.contains(parts[3].first!))
    }

    // MARK: - scaffoldFilePath per target

    func testScaffoldFilePathForIOS() {
        let path = ScaffoldGenerator.scaffoldFilePath(for: .ios)
        XCTAssertEqual(path, "full-app/ios-swiftui/Sources/GeneratedApp/GeneratedDashboardView.swift")
    }

    func testScaffoldFilePathForMacOS() {
        let path = ScaffoldGenerator.scaffoldFilePath(for: .macos)
        XCTAssertEqual(path, "full-app/macos-swiftui/Sources/GeneratedApp/GeneratedDashboardView.swift")
    }

    func testScaffoldFilePathForWeb() {
        let path = ScaffoldGenerator.scaffoldFilePath(for: .web)
        XCTAssertEqual(path, "full-app/web/index.html")
    }

    // MARK: - buildDesignCodeDiffEntries

    func testBuildDesignCodeDiffEntriesDetectsMissingState() {
        let stateID = UUID(uuidString: "00000000-0000-0000-0000-000000000810")!
        let controlID = UUID(uuidString: "00000000-0000-0000-0000-000000000811")!
        let manifest = makeManifest(
            inferredStates: [
                InferredState(id: stateID, name: "Loading", triggerControlID: controlID, triggerLabel: "Load", description: "Loading state", confidence: 0.9),
            ]
        )

        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: .web,
            manifest: manifest,
            scaffoldContent: "<html><body>Hello</body></html>",
            filePath: "full-app/web/index.html"
        )

        XCTAssertTrue(diffs.contains(where: { $0.category == "state" && $0.detail.contains("Loading") }))
    }

    func testBuildDesignCodeDiffEntriesDetectsMissingControl() {
        let controlID = UUID(uuidString: "00000000-0000-0000-0000-000000000812")!
        let manifest = makeManifest(
            inferredControls: [
                InferredControl(id: controlID, name: "save", label: "Save", kind: .button, role: .buttonPrimary, sourceElementID: nil, frame: nil, confidence: 0.9, rationale: "Primary CTA"),
            ]
        )

        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: .web,
            manifest: manifest,
            scaffoldContent: "<html><body>No controls here</body></html>",
            filePath: "full-app/web/index.html"
        )

        XCTAssertTrue(diffs.contains(where: { $0.category == "control" && $0.detail.contains("Save") }))
    }

    func testBuildDesignCodeDiffEntriesDetectsMissingComponentMetadata() {
        let specID = UUID(uuidString: "00000000-0000-0000-0000-000000000813")!
        let manifest = makeManifest(
            componentSpecs: [
                ComponentSpec(id: specID, name: "NavBar", kind: .nav, elementIDs: [], notes: "test"),
            ]
        )

        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: .web,
            manifest: manifest,
            scaffoldContent: "<html><body>Plain page with no special refs</body></html>",
            filePath: "full-app/web/index.html"
        )

        XCTAssertTrue(diffs.contains(where: { $0.category == "component" }))
    }

    func testBuildDesignCodeDiffEntriesDetectsMissingTokenMapping() {
        let manifest = makeManifest(
            designTokens: DesignTokenSet(
                colors: ["primary": "#FF0000", "secondary": "#00FF00"],
                typography: [:],
                spacing: [:],
                radius: [:],
                shadow: [:],
                motion: [:]
            )
        )

        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: .web,
            manifest: manifest,
            scaffoldContent: "<html><body>Plain page with no design system refs</body></html>",
            filePath: "full-app/web/index.html"
        )

        XCTAssertTrue(diffs.contains(where: { $0.category == "tokens" }))
    }

    func testBuildDesignCodeDiffEntriesReturnsNoDriftWhenContentMatchesAll() {
        let stateID = UUID(uuidString: "00000000-0000-0000-0000-000000000814")!
        let controlID = UUID(uuidString: "00000000-0000-0000-0000-000000000815")!
        let manifest = makeManifest(
            inferredControls: [
                InferredControl(id: controlID, name: "export", label: "Export", kind: .button, role: .buttonPrimary, sourceElementID: nil, frame: nil, confidence: 0.9, rationale: "CTA"),
            ],
            inferredStates: [
                InferredState(id: stateID, name: "Ready", triggerControlID: controlID, triggerLabel: "Export", description: "Ready state", confidence: 0.9),
            ]
        )

        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: .web,
            manifest: manifest,
            scaffoldContent: "Ready state with Export button component and token mapping",
            filePath: "full-app/web/index.html"
        )

        // Should only have the "no drift" summary entry
        XCTAssertTrue(diffs.contains(where: { $0.category == "summary" }))
        XCTAssertFalse(diffs.contains(where: { $0.category == "state" }))
    }

    // MARK: - buildReadme format

    func testBuildReadmeContainsProjectNameAndTarget() {
        let manifest = makeManifest()

        let readme = ScaffoldGenerator.buildReadme(
            for: .web,
            manifest: manifest,
            qualityGateScoreLine: "Score: 85"
        )

        XCTAssertTrue(readme.contains("TestProject"))
        XCTAssertTrue(readme.contains("Web"))
        XCTAssertTrue(readme.contains("Score: 85"))
        XCTAssertTrue(readme.contains("Dashboard"))
    }

    func testBuildReadmeIncludesBenchmarkAndReviewInfo() {
        let manifest = makeManifest()

        let readme = ScaffoldGenerator.buildReadme(
            for: .ios,
            manifest: manifest,
            qualityGateScoreLine: "N/A"
        )

        XCTAssertTrue(readme.contains("Review State"))
        XCTAssertTrue(readme.contains("Benchmark"))
        XCTAssertTrue(readme.contains("iOS"))
    }

    // MARK: - buildScaffoldChecklist

    func testBuildScaffoldChecklistContainsTargetTitle() {
        let manifest = makeManifest(capabilities: ["User auth", "Data export"])

        let checklist = ScaffoldGenerator.buildScaffoldChecklist(for: .web, manifest: manifest)

        XCTAssertTrue(checklist.contains("Web"))
        XCTAssertTrue(checklist.contains("User auth"))
        XCTAssertTrue(checklist.contains("Data export"))
    }

    func testBuildScaffoldChecklistIncludesInferredStateCount() {
        let stateID = UUID(uuidString: "00000000-0000-0000-0000-000000000820")!
        let controlID = UUID(uuidString: "00000000-0000-0000-0000-000000000821")!
        let manifest = makeManifest(
            inferredStates: [
                InferredState(id: stateID, name: "Idle", triggerControlID: controlID, triggerLabel: "Start", description: "Idle", confidence: 0.9),
            ]
        )

        let checklist = ScaffoldGenerator.buildScaffoldChecklist(for: .ios, manifest: manifest)

        XCTAssertTrue(checklist.contains("1"))
        XCTAssertTrue(checklist.contains("states"))
    }

    func testBuildScaffoldChecklistFallsBackWhenNoCapabilities() {
        let manifest = makeManifest(capabilities: [])

        let checklist = ScaffoldGenerator.buildScaffoldChecklist(for: .macos, manifest: manifest)

        XCTAssertTrue(checklist.contains("Define initial core capabilities"))
    }
}

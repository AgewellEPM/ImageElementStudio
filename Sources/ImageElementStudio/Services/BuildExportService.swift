import Combine
import Foundation

// MARK: - BuildExportService

/// Owns all build-setup and export logic previously living in StudioViewModel.
/// The ViewModel forwards public methods to this service and subscribes to
/// objectWillChange so SwiftUI views update automatically.
@MainActor
final class BuildExportService: ObservableObject {

    // MARK: - Nested Types

    struct BuildManifest: Codable {
        var schemaVersion: Int
        var projectName: String
        var projectID: String
        var target: String
        var generatedAt: Date
        var deterministicHash: String
        var appType: String?
        var productIntent: String?
        var capabilities: [String]
        var mirrorScore: Double?
        var inferredControls: [InferredControl]
        var inferredStates: [InferredState]
        var suggestedStateArtboards: [SuggestedArtboard]
        var designTokens: DesignTokenSet?
        var tokenRevisions: [TokenRevision]
        var componentSpecs: [ComponentSpec]
        var componentInstances: [ComponentInstance]
        var strategySpec: StrategySpec?
        var importLossReport: ImportLossReport?
        var reviewComments: [DesignReviewComment]
        var reviewApprovalState: String
        var benchmarkReport: BenchmarkRunReport?
        var benchmarkHistoryCount: Int
        var benchmarkTrendScore: BenchmarkTrendScore?
        var pipelineMode: String
        var stylePreset: String
        var activeArtboardName: String
        var artboardCount: Int
        var elementCount: Int
        var memorySnapshotCount: Int
        var analysisDocument: AnalysisDocument
    }

    struct DeterministicManifestSnapshot: Codable, Hashable {
        var schemaVersion: Int
        var target: String
        var projectName: String
        var projectID: String
        var pipelineMode: String
        var stylePreset: String
        var activeArtboardName: String
        var elementCount: Int
        var inferredControls: [String]
        var inferredStates: [String]
        var componentSpecs: [String]
        var tokenColorKeys: [String]
        var reviewApprovalState: String
        var benchmarkPassed: Bool
        var benchmarkStepPassRate: Double
        var benchmarkMedianStepLatencyMilliseconds: Double?
        var benchmarkTrendPassRate: Double?
        var benchmarkTrendMedianStepLatencyMilliseconds: Double?
    }

    struct DeterministicDiffSnapshot: Codable, Hashable {
        struct Entry: Codable, Hashable {
            var category: String
            var title: String
            var detail: String
            var impactScore: Double
        }

        var target: String
        var entries: [Entry]
    }

    struct DeterministicAppSpecSnapshot: Codable, Hashable {
        var target: String
        var initialState: String
        var states: [String]
        var controls: [String]
        var capabilities: [String]
        var screens: [String]
        var transitions: [String]
    }

    // MARK: - Build Context

    /// A snapshot of the ViewModel state needed for build and export operations.
    /// Passed into service methods instead of giving the service a reference to the VM.
    struct BuildContext {
        var projectName: String
        var projectID: String
        var pipelineMode: PipelineMode
        var mockupStylePreset: MockupStylePreset
        var artboards: [Artboard]
        var latestScope: ProductScopeSnapshot?
        var latestBlueprint: BuildBlueprint?
        var latestDesignTokens: DesignTokenSet?
        var tokenRevisions: [TokenRevision]
        var latestComponentSpecs: [ComponentSpec]
        var componentInstances: [ComponentInstance]
        var acceptedStrategySpec: StrategySpec?
        var importLossReport: ImportLossReport?
        var reviewComments: [DesignReviewComment]
        var reviewApprovalState: String
        var latestBenchmarkReport: BenchmarkRunReport?
        var benchmarkHistory: [BenchmarkRunReport]
        var benchmarkTrendScore: BenchmarkTrendScore?
        var designCodeDiffs: [DesignCodeDiffEntry]
        var latestBuildQualityReport: BuildQualityReport?
        var canExportBuildArtifacts: Bool
        var reviewGateBlockReason: String?
        var reviewGateStatusLine: String
        var overdueReviewCommentCount: Int
        var unresolvedReviewCommentCount: Int
        var qualityGateScoreLine: String
        var memorySnapshotCount: Int
        var memoryEntryCount: Int
        var activeArtboard: Artboard?
        var document: AnalysisDocument
        var strategySessionStage: String?
        var acceptedStrategySpecConfidence: Double?
    }

    // MARK: - Result Types

    struct BuildSetupResult {
        var outputDirectory: URL
        var qualityReport: BuildQualityReport
        var designCodeDiffs: [DesignCodeDiffEntry]
    }

    struct FullStackBuildResult {
        var summary: FullStackBuildSummary
        var enterpriseReport: EnterpriseReadinessReport
        var rootOutputDirectory: URL
    }

    // MARK: - Private Types

    enum BuildSetupMode {
        case manual
        case realtime
    }

    // MARK: - Init

    init() {}

    // MARK: - Public Build / Export Methods

    /// Sets up a build for a single target. Returns the output directory and quality results.
    func setupBuild(
        for target: StudioViewModel.BuildTarget,
        context: BuildContext,
        outputDirectoryOverride: URL? = nil
    ) throws -> BuildSetupResult {
        let outputDirectory = try outputDirectoryOverride
            ?? makeBuildOutputDirectory(for: target, mode: .manual, projectName: context.projectName)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let deterministicHash = computeDeterministicHash(target: target, context: context)
        let generatedAt = Date()
        let manifest = makeBuildManifest(
            target: target,
            deterministicHash: deterministicHash,
            context: context,
            generatedAt: generatedAt
        )

        let encoder = makeEncoder()
        let manifestData = try encoder.encode(manifest)
        let manifestURL = outputDirectory.appendingPathComponent("build-manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)

        let readmeURL = outputDirectory.appendingPathComponent("README.md")
        try ScaffoldGenerator.buildReadme(
            for: target,
            manifest: manifest,
            qualityGateScoreLine: context.qualityGateScoreLine
        ).write(to: readmeURL, atomically: true, encoding: .utf8)

        let scaffoldURL = outputDirectory.appendingPathComponent("scaffold-todo.md")
        try ScaffoldGenerator.buildScaffoldChecklist(for: target, manifest: manifest)
            .write(to: scaffoldURL, atomically: true, encoding: .utf8)

        try ScaffoldGenerator.writeGeneratedScaffold(for: target, manifest: manifest, to: outputDirectory)
        try ScaffoldGenerator.writeGeneratedFullApp(
            for: target,
            manifest: manifest,
            deterministicHash: deterministicHash,
            generatedAt: generatedAt,
            encoder: encoder,
            to: outputDirectory
        )
        try writeBenchmarkTrendArtifact(
            target: target,
            outputDirectory: outputDirectory,
            deterministicHash: deterministicHash,
            generatedAt: generatedAt,
            encoder: encoder,
            context: context
        )

        let smokeChecks = runSmokeChecks(for: target, in: outputDirectory)
        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: target,
            manifest: manifest,
            outputDirectory: outputDirectory
        )
        let passCount = smokeChecks.filter(\.passed).count
        let passRate = smokeChecks.isEmpty ? 1.0 : Double(passCount) / Double(smokeChecks.count)
        let qualityGateSummary = makeQualityGateSummary(
            generatedAt: generatedAt,
            smokeChecks: smokeChecks,
            diffEntries: diffs,
            benchmarkPassRate: context.benchmarkTrendScore?.passRate ?? context.latestBenchmarkReport?.stepPassRate,
            reviewGatePassed: context.canExportBuildArtifacts,
            overdueCommentCount: context.overdueReviewCommentCount,
            reviewGateBlockReason: context.reviewGateBlockReason
        )
        let qualityReport = BuildQualityReport(
            generatedAt: Date(),
            deterministicHash: deterministicHash,
            smokeChecks: smokeChecks,
            passRate: passRate,
            diffs: diffs,
            qualityGateSummary: qualityGateSummary
        )
        let qualityData = try encoder.encode(qualityReport)
        let qualityURL = outputDirectory.appendingPathComponent("build-quality-report.json")
        try qualityData.write(to: qualityURL, options: .atomic)

        return BuildSetupResult(
            outputDirectory: outputDirectory,
            qualityReport: qualityReport,
            designCodeDiffs: diffs
        )
    }

    /// Sets up a realtime build. Returns the output directory path on success.
    func setupRealtimeBuild(
        for target: StudioViewModel.BuildTarget,
        context: BuildContext
    ) throws -> URL {
        let outputDirectory = try makeBuildOutputDirectory(
            for: target,
            mode: .realtime,
            projectName: context.projectName
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let deterministicHash = computeDeterministicHash(target: target, context: context)
        let generatedAt = Date()
        let manifest = makeBuildManifest(
            target: target,
            deterministicHash: deterministicHash,
            context: context,
            generatedAt: generatedAt
        )

        let encoder = makeEncoder()
        let manifestData = try encoder.encode(manifest)
        let manifestURL = outputDirectory.appendingPathComponent("build-manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)

        let readmeURL = outputDirectory.appendingPathComponent("README.md")
        try ScaffoldGenerator.buildReadme(
            for: target,
            manifest: manifest,
            qualityGateScoreLine: context.qualityGateScoreLine
        ).write(to: readmeURL, atomically: true, encoding: .utf8)

        let scaffoldURL = outputDirectory.appendingPathComponent("scaffold-todo.md")
        try ScaffoldGenerator.buildScaffoldChecklist(for: target, manifest: manifest)
            .write(to: scaffoldURL, atomically: true, encoding: .utf8)

        try ScaffoldGenerator.writeGeneratedScaffold(for: target, manifest: manifest, to: outputDirectory)
        try ScaffoldGenerator.writeGeneratedFullApp(
            for: target,
            manifest: manifest,
            deterministicHash: deterministicHash,
            generatedAt: generatedAt,
            encoder: encoder,
            to: outputDirectory
        )
        try writeBenchmarkTrendArtifact(
            target: target,
            outputDirectory: outputDirectory,
            deterministicHash: deterministicHash,
            generatedAt: generatedAt,
            encoder: encoder,
            context: context
        )

        let smokeChecks = runSmokeChecks(for: target, in: outputDirectory)
        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: target,
            manifest: manifest,
            outputDirectory: outputDirectory
        )
        let passCount = smokeChecks.filter(\.passed).count
        let passRate = smokeChecks.isEmpty ? 1.0 : Double(passCount) / Double(smokeChecks.count)
        let qualityGateSummary = makeQualityGateSummary(
            generatedAt: generatedAt,
            smokeChecks: smokeChecks,
            diffEntries: diffs,
            benchmarkPassRate: context.benchmarkTrendScore?.passRate ?? context.latestBenchmarkReport?.stepPassRate,
            reviewGatePassed: context.canExportBuildArtifacts,
            overdueCommentCount: context.overdueReviewCommentCount,
            reviewGateBlockReason: context.reviewGateBlockReason
        )
        let qualityReport = BuildQualityReport(
            generatedAt: Date(),
            deterministicHash: deterministicHash,
            smokeChecks: smokeChecks,
            passRate: passRate,
            diffs: diffs,
            qualityGateSummary: qualityGateSummary
        )
        let qualityData = try encoder.encode(qualityReport)
        let qualityURL = outputDirectory.appendingPathComponent("build-quality-report.json")
        try qualityData.write(to: qualityURL, options: .atomic)

        return outputDirectory
    }

    /// Runs the full-stack build across all targets and returns summary + enterprise report.
    func generateFullStackBuild(
        context: BuildContext
    ) throws -> FullStackBuildResult {
        let targetOrder: [StudioViewModel.BuildTarget] = [.web, .ios, .macos]
        let rootOutputDirectory = try makeFullStackBuildOutputDirectory(projectName: context.projectName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = makeEncoder()
        var targetResults: [FullStackTargetResult] = []

        for target in targetOrder {
            let targetDirectory = rootOutputDirectory.appendingPathComponent(target.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            _ = try setupBuild(
                for: target,
                context: context,
                outputDirectoryOverride: targetDirectory
            )
            let qualityReport = try ScaffoldGenerator.loadBuildQualityReport(from: targetDirectory, decoder: decoder)
            let smokePassCount = qualityReport.smokeChecks.filter(\.passed).count
            let smokeTotalCount = qualityReport.smokeChecks.count
            let smokePassRate = smokeTotalCount == 0 ? 0 : Double(smokePassCount) / Double(smokeTotalCount)
            let fullAppPassRate = fullAppSmokePassRate(in: qualityReport.smokeChecks)
            let qualitySummary = qualityReport.qualityGateSummary ?? makeQualityGateSummary(
                generatedAt: qualityReport.generatedAt,
                smokeChecks: qualityReport.smokeChecks,
                diffEntries: qualityReport.diffs,
                benchmarkPassRate: context.benchmarkTrendScore?.passRate ?? context.latestBenchmarkReport?.stepPassRate,
                reviewGatePassed: context.canExportBuildArtifacts,
                overdueCommentCount: context.overdueReviewCommentCount,
                reviewGateBlockReason: context.reviewGateBlockReason
            )
            var blockingIssues = qualitySummary.blockingIssues
            if smokePassRate < Constants.QualityGate.smokePassRateThreshold {
                blockingIssues.append("Smoke-check pass rate below 90%.")
            }
            if fullAppPassRate < Constants.QualityGate.fullAppPassRateThreshold {
                blockingIssues.append("Full-app smoke-check pass rate below 90%.")
            }
            let dedupedIssues = uniqueStrings(blockingIssues)
            let passed = smokePassRate >= Constants.QualityGate.smokePassRateThreshold
                && fullAppPassRate >= Constants.QualityGate.fullAppPassRateThreshold
                && qualitySummary.status == .pass
                && dedupedIssues.isEmpty

            targetResults.append(
                FullStackTargetResult(
                    target: target.rawValue,
                    outputPath: targetDirectory.path,
                    deterministicHash: qualityReport.deterministicHash,
                    smokePassCount: smokePassCount,
                    smokeTotalCount: smokeTotalCount,
                    smokePassRate: smokePassRate,
                    fullAppPassRate: fullAppPassRate,
                    qualityScore: qualitySummary.overallScore,
                    passed: passed,
                    blockingIssues: dedupedIssues
                )
            )
        }

        let aggregateScore: Double
        if targetResults.isEmpty {
            aggregateScore = 0
        } else {
            aggregateScore = targetResults.map(\.qualityScore).reduce(0, +) / Double(targetResults.count)
        }
        let failedTargets = targetResults.filter { !$0.passed }.map(\.target)
        var blockingIssues: [String] = []
        if !failedTargets.isEmpty {
            blockingIssues.append("Targets failing quality checks: \(failedTargets.joined(separator: ", ")).")
        }
        for result in targetResults where !result.passed {
            if let firstIssue = result.blockingIssues.first {
                blockingIssues.append("\(result.target): \(firstIssue)")
            }
        }
        let summary = FullStackBuildSummary(
            runID: UUID(),
            generatedAt: Date(),
            projectName: context.projectName,
            projectID: context.projectID,
            reviewGatePassed: context.canExportBuildArtifacts,
            aggregateScore: aggregateScore,
            allTargetsPassed: failedTargets.isEmpty,
            targetResults: targetResults,
            blockingIssues: uniqueStrings(blockingIssues)
        )

        let enterpriseReport = makeEnterpriseReadinessReport(from: summary, context: context)

        let summaryURL = rootOutputDirectory.appendingPathComponent("full-stack-summary.json")
        try encoder.encode(summary).write(to: summaryURL, options: .atomic)

        let enterpriseURL = rootOutputDirectory.appendingPathComponent("enterprise-readiness-report.json")
        try encoder.encode(enterpriseReport).write(to: enterpriseURL, options: .atomic)

        let validationScriptURL = rootOutputDirectory.appendingPathComponent("run-full-app-checks.sh")
        try fullStackValidationScript().write(to: validationScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: validationScriptURL.path
        )

        return FullStackBuildResult(
            summary: summary,
            enterpriseReport: enterpriseReport,
            rootOutputDirectory: rootOutputDirectory
        )
    }

    /// Builds a confirmation lines summary for a target before build export.
    func buildConfirmationLines(
        for target: StudioViewModel.BuildTarget,
        context: BuildContext
    ) -> [String] {
        let boardSummary: String
        if let board = context.activeArtboard {
            boardSummary = "\(board.name) \(board.width)x\(board.height), \(board.elements.count) elements"
        } else {
            boardSummary = "No active artboard"
        }

        let scopeSummary = context.latestScope?.appType ?? "No semantic scope yet"
        let capabilities = context.latestScope?.keyCapabilities.prefix(3).joined(separator: ", ")
            ?? "Will use current screen layout and OCR mapping"
        let mirrorScore: String
        if let score = context.latestBlueprint?.mirrorScore {
            mirrorScore = "\(Int((score * 100).rounded()))%"
        } else {
            mirrorScore = "Pending analysis"
        }
        let stateCount = context.latestBlueprint?.states.count ?? 0
        let controlCount = context.latestBlueprint?.controls.count ?? 0

        return [
            "Target: \(target.title) (\(target.buildLabel))",
            "Project: \(context.projectName)",
            "Active Artboard: \(boardSummary)",
            "Inferred Scope: \(scopeSummary)",
            "Capabilities: \(capabilities)",
            "Mirror Score: \(mirrorScore)",
            "Controls + States: \(controlCount) controls, \(stateCount) states",
            "Memory Snapshots: \(context.memoryEntryCount)",
            "Review Gate: \(context.canExportBuildArtifacts ? "Ready" : "Blocked")",
        ]
    }

    /// Computes a deterministic manifest snapshot for testing/comparison.
    func deterministicManifestSnapshot(
        for target: StudioViewModel.BuildTarget,
        context: BuildContext
    ) -> DeterministicManifestSnapshot {
        let referenceDate = Date(timeIntervalSince1970: 0)
        let referenceContext = context.withReferenceDate(referenceDate)
        let deterministicHash = computeDeterministicHash(target: target, context: referenceContext)
        let manifest = makeBuildManifest(
            target: target,
            deterministicHash: deterministicHash,
            context: referenceContext,
            generatedAt: referenceDate
        )
        return DeterministicManifestSnapshot(
            schemaVersion: manifest.schemaVersion,
            target: manifest.target,
            projectName: manifest.projectName,
            projectID: manifest.projectID,
            pipelineMode: manifest.pipelineMode,
            stylePreset: manifest.stylePreset,
            activeArtboardName: manifest.activeArtboardName,
            elementCount: manifest.elementCount,
            inferredControls: manifest.inferredControls.map(\.label).sorted(),
            inferredStates: manifest.inferredStates.map(\.name).sorted(),
            componentSpecs: manifest.componentSpecs.map(\.name).sorted(),
            tokenColorKeys: manifest.designTokens?.colors.keys.sorted() ?? [],
            reviewApprovalState: manifest.reviewApprovalState,
            benchmarkPassed: manifest.benchmarkReport?.passed ?? false,
            benchmarkStepPassRate: manifest.benchmarkReport?.stepPassRate ?? 0,
            benchmarkMedianStepLatencyMilliseconds: manifest.benchmarkReport?.medianStepLatencyMilliseconds,
            benchmarkTrendPassRate: manifest.benchmarkTrendScore?.passRate,
            benchmarkTrendMedianStepLatencyMilliseconds: manifest.benchmarkTrendScore?.medianStepLatencyMilliseconds
        )
    }

    /// Computes a deterministic diff snapshot for testing/comparison.
    func deterministicDiffSnapshot(
        for target: StudioViewModel.BuildTarget,
        scaffoldContent: String,
        context: BuildContext
    ) -> DeterministicDiffSnapshot {
        let referenceDate = Date(timeIntervalSince1970: 0)
        let referenceContext = context.withReferenceDate(referenceDate)
        let deterministicHash = computeDeterministicHash(target: target, context: referenceContext)
        let manifest = makeBuildManifest(
            target: target,
            deterministicHash: deterministicHash,
            context: referenceContext,
            generatedAt: referenceDate
        )
        let filePath = ScaffoldGenerator.scaffoldFilePath(for: target)
        let diffs = ScaffoldGenerator.buildDesignCodeDiffEntries(
            for: target,
            manifest: manifest,
            scaffoldContent: scaffoldContent,
            filePath: filePath
        )
        return DeterministicDiffSnapshot(
            target: target.rawValue,
            entries: diffs.map { diff in
                DeterministicDiffSnapshot.Entry(
                    category: diff.category,
                    title: diff.title,
                    detail: diff.detail,
                    impactScore: diff.impactScore
                )
            }
        )
    }

    /// Computes a deterministic app-spec snapshot for testing/comparison.
    func deterministicAppSpecSnapshot(
        for target: StudioViewModel.BuildTarget,
        context: BuildContext
    ) -> DeterministicAppSpecSnapshot {
        let referenceDate = Date(timeIntervalSince1970: 0)
        let referenceContext = context.withReferenceDate(referenceDate)
        let deterministicHash = computeDeterministicHash(target: target, context: referenceContext)
        let manifest = makeBuildManifest(
            target: target,
            deterministicHash: deterministicHash,
            context: referenceContext,
            generatedAt: referenceDate
        )
        let appSpec = ScaffoldGenerator.generatedAppSpec(
            manifest: manifest,
            target: target,
            deterministicHash: deterministicHash,
            generatedAt: referenceDate
        )
        return DeterministicAppSpecSnapshot(
            target: target.rawValue,
            initialState: appSpec.initialState,
            states: appSpec.states,
            controls: appSpec.controls,
            capabilities: appSpec.capabilities,
            screens: appSpec.screens.map { "\($0.name):\($0.state)" },
            transitions: appSpec.transitions.map { "\($0.controlLabel):\($0.fromState)->\($0.toState)" }
        )
    }
}

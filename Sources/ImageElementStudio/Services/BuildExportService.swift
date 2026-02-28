import AppKit
import Combine
import CryptoKit
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

    private enum BuildSetupMode {
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
            if smokePassRate < 0.9 {
                blockingIssues.append("Smoke-check pass rate below 90%.")
            }
            if fullAppPassRate < 0.9 {
                blockingIssues.append("Full-app smoke-check pass rate below 90%.")
            }
            let dedupedIssues = uniqueStrings(blockingIssues)
            let passed = smokePassRate >= 0.9
                && fullAppPassRate >= 0.9
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

    // MARK: - Quality Gate Summary (public for ViewModel forwarding)

    func makeQualityGateSummary(
        generatedAt: Date,
        smokeChecks: [SmokeCheckResult],
        diffEntries: [DesignCodeDiffEntry],
        benchmarkPassRate: Double?,
        reviewGatePassed: Bool,
        overdueCommentCount: Int,
        reviewGateBlockReason: String?
    ) -> QualityGateSummary {
        let smokePassRate: Double
        if smokeChecks.isEmpty {
            smokePassRate = 0.5
        } else {
            let passCount = smokeChecks.filter(\.passed).count
            smokePassRate = Double(passCount) / Double(smokeChecks.count)
        }

        let fullAppChecks = smokeChecks.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains("full app")
        }
        let fullAppPassRate: Double
        if fullAppChecks.isEmpty {
            fullAppPassRate = 0.5
        } else {
            let passCount = fullAppChecks.filter(\.passed).count
            fullAppPassRate = Double(passCount) / Double(fullAppChecks.count)
        }

        let diffHealthScore: Double
        if diffEntries.isEmpty {
            diffHealthScore = 0.5
        } else {
            let averageImpact = diffEntries.map(\.impactScore).reduce(0, +) / Double(diffEntries.count)
            diffHealthScore = max(0, 1 - min(1, averageImpact))
        }

        let normalizedBenchmarkPassRate = max(0, min(1, benchmarkPassRate ?? 0.5))
        let smokePoints = smokePassRate * 30
        let fullAppPoints = fullAppPassRate * 15
        let diffPoints = diffHealthScore * 20
        let benchmarkPoints = normalizedBenchmarkPassRate * 20
        let reviewPoints = reviewGatePassed ? 15.0 : 0.0
        let overduePenalty = min(Double(overdueCommentCount) * 2.0, 10.0)
        let totalScore = max(
            0,
            min(100, smokePoints + fullAppPoints + diffPoints + benchmarkPoints + reviewPoints - overduePenalty)
        )

        let status: QualityGateStatus
        switch totalScore {
        case 85...:
            status = .pass
        case 65..<85:
            status = .warning
        default:
            status = .fail
        }

        var issues: [String] = []
        if smokeChecks.isEmpty {
            issues.append("No smoke checks captured yet.")
        } else if smokePassRate < 0.9 {
            issues.append("Smoke-check pass rate below 90%.")
        }
        if fullAppChecks.isEmpty {
            issues.append("No full-app smoke checks captured yet.")
        } else if fullAppPassRate < 0.9 {
            issues.append("Full-app smoke checks below 90%.")
        }
        if diffEntries.isEmpty {
            issues.append("No design/code diff artifacts available.")
        } else if diffEntries.contains(where: { $0.impactScore >= 0.7 }) {
            issues.append("High-impact design/code drifts detected.")
        }
        if normalizedBenchmarkPassRate < 0.8 {
            issues.append("Benchmark trend pass-rate below 80%.")
        }
        if !reviewGatePassed {
            issues.append(reviewGateBlockReason ?? "Review gate is blocking export.")
        }
        if overdueCommentCount > 0 {
            issues.append("\(overdueCommentCount) review comments are overdue.")
        }

        return QualityGateSummary(
            generatedAt: generatedAt,
            overallScore: totalScore,
            status: status,
            smokePassRate: smokePassRate,
            fullAppPassRate: fullAppPassRate,
            diffHealthScore: diffHealthScore,
            benchmarkPassRate: normalizedBenchmarkPassRate,
            reviewGatePassed: reviewGatePassed,
            overdueCommentCount: overdueCommentCount,
            blockingIssues: issues
        )
    }

    // MARK: - Enterprise Readiness

    func makeEnterpriseReadinessReport(
        from summary: FullStackBuildSummary,
        context: BuildContext
    ) -> EnterpriseReadinessReport {
        let benchmarkPassRate = context.benchmarkTrendScore?.passRate
            ?? context.latestBenchmarkReport?.stepPassRate ?? 0
        let importCleanupPercent = context.importLossReport?.estimatedManualCleanupPercent ?? 0
        let deterministicHashes = summary.targetResults.map(\.deterministicHash).filter { !$0.isEmpty }
        let hashesUnique = !deterministicHashes.isEmpty
            && Set(deterministicHashes).count == summary.targetResults.count
        let highImpactDiffs = context.designCodeDiffs.contains { $0.impactScore >= 0.7 }
        let unresolvedComments = context.unresolvedReviewCommentCount

        let checks: [EnterpriseReadinessCheck] = [
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|targets"),
                name: "All target full-app runs passed",
                weight: 25,
                passed: summary.allTargetsPassed,
                detail: summary.allTargetsPassed
                    ? "web, ios, macos all passed quality gates."
                    : "One or more targets failed quality gates."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|aggregate"),
                name: "Aggregate quality score >= 85",
                weight: 20,
                passed: summary.aggregateScore >= 85,
                detail: "Current aggregate score: \(Int(summary.aggregateScore.rounded()))."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|review"),
                name: "Review approval gate passed",
                weight: 15,
                passed: context.canExportBuildArtifacts,
                detail: context.canExportBuildArtifacts
                    ? "Approval is approved and comments are resolved."
                    : context.reviewGateStatusLine
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|benchmark"),
                name: "Benchmark trend pass-rate >= 85%",
                weight: 10,
                passed: benchmarkPassRate >= 0.85,
                detail: "Current benchmark trend pass-rate: \(Int((benchmarkPassRate * 100).rounded()))%."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|interop"),
                name: "Import cleanup estimate <= 20%",
                weight: 10,
                passed: importCleanupPercent <= 20,
                detail: "Estimated manual cleanup: \(Int(importCleanupPercent.rounded()))%."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|hashes"),
                name: "Deterministic hashes are present and unique",
                weight: 10,
                passed: hashesUnique,
                detail: hashesUnique
                    ? "Each target has a unique deterministic hash."
                    : "Deterministic hashes are missing or duplicated."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|drift"),
                name: "No high-impact design/code drifts",
                weight: 5,
                passed: !highImpactDiffs,
                detail: highImpactDiffs
                    ? "Detected design/code drift with impact >= 0.7."
                    : "No high-impact drifts detected."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|sla"),
                name: "No unresolved review comments",
                weight: 5,
                passed: unresolvedComments == 0,
                detail: unresolvedComments == 0
                    ? "All review comments resolved."
                    : "\(unresolvedComments) unresolved comments remain."
            ),
        ]

        let score = checks.filter(\.passed).map(\.weight).reduce(0, +)
        let blockers = checks.filter { !$0.passed && $0.weight >= 10 }.map { "\($0.name): \($0.detail)" }
        let recommendedActions = uniqueStrings(
            checks.filter { !$0.passed }.map { check in
                switch check.name {
                case "All target full-app runs passed":
                    return "Fix failing target checks in full-stack-summary.json and rerun build full app."
                case "Aggregate quality score >= 85":
                    return "Raise smoke/full-app pass rates and reduce drift impact until aggregate score is >= 85."
                case "Review approval gate passed":
                    return "Set review to Approved and resolve all open comments."
                case "Benchmark trend pass-rate >= 85%":
                    return "Run benchmark auto-fix loop until trend pass-rate reaches 85%."
                case "Import cleanup estimate <= 20%":
                    return "Improve import mapping and token/component normalization to reduce manual cleanup."
                case "Deterministic hashes are present and unique":
                    return "Regenerate build artifacts and validate deterministic hash generation per target."
                case "No high-impact design/code drifts":
                    return "Close high-impact state/control/token drift issues in generated full-app outputs."
                case "No unresolved review comments":
                    return "Resolve or explicitly close all outstanding review comments."
                default:
                    return "Resolve failed enterprise readiness checks and rerun full-stack build."
                }
            }
        )

        let status: EnterpriseReadinessStatus
        if score >= 85 && blockers.isEmpty {
            status = .pass
        } else if score >= 65 {
            status = .warning
        } else {
            status = .fail
        }

        return EnterpriseReadinessReport(
            runID: summary.runID,
            generatedAt: Date(),
            projectName: context.projectName,
            projectID: context.projectID,
            status: status,
            score: score,
            checks: checks,
            blockers: uniqueStrings(blockers + summary.blockingIssues),
            recommendedActions: recommendedActions
        )
    }

    // MARK: - Utility (internal use, also used by ViewModel via forwarding)

    func slugified(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        let lowercase = value.lowercased()
        var output = ""
        var previousDash = false

        for scalar in lowercase.unicodeScalars {
            if allowed.contains(Character(scalar)) {
                output.unicodeScalars.append(scalar)
                previousDash = false
            } else if !previousDash {
                output.append("-")
                previousDash = true
            }
        }

        while output.hasPrefix("-") { output.removeFirst() }
        while output.hasSuffix("-") { output.removeLast() }
        return output.isEmpty ? "project" : output
    }

    func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            ordered.append(cleaned)
        }
        return ordered
    }

    // MARK: - Private Helpers

    private func makeFullStackBuildOutputDirectory(projectName: String) throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let projectSlug = slugified(projectName)
        let directory = baseDirectory
            .appendingPathComponent("ImageElementStudioBuilds", isDirectory: true)
            .appendingPathComponent(projectSlug, isDirectory: true)
            .appendingPathComponent("\(timestamp)-full-stack", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeBuildOutputDirectory(
        for target: StudioViewModel.BuildTarget,
        mode: BuildSetupMode,
        projectName: String
    ) throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let projectSlug = slugified(projectName)
        let folderName: String

        switch mode {
        case .manual:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            folderName = "\(timestamp)-\(target.rawValue)"
        case .realtime:
            folderName = "realtime-\(target.rawValue)"
        }

        let directory = baseDirectory
            .appendingPathComponent("ImageElementStudioBuilds", isDirectory: true)
            .appendingPathComponent(projectSlug, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fullAppSmokePassRate(in checks: [SmokeCheckResult]) -> Double {
        let fullAppChecks = checks.filter { check in
            (check.name ?? "").localizedCaseInsensitiveContains("full app")
        }
        guard !fullAppChecks.isEmpty else { return 0 }
        let passCount = fullAppChecks.filter(\.passed).count
        return Double(passCount) / Double(fullAppChecks.count)
    }

    private func fullStackValidationScript() -> String {
        """
        #!/usr/bin/env bash
        set -euo pipefail

        echo "[1/3] web full-app syntax"
        if command -v node >/dev/null; then
          node --check ./web/full-app/web/app.js
        else
          grep -q "Generated full app blueprint" ./web/full-app/web/app.js
        fi

        echo "[2/3] iOS full-app project generation"
        if command -v xcodegen >/dev/null; then
          (cd ./ios/full-app/ios-swiftui && xcodegen generate >/dev/null)
        else
          test -f ./ios/full-app/ios-swiftui/project.yml
        fi

        echo "[3/4] macOS full-app build"
        (cd ./macos/full-app/macos-swiftui && swift build)

        echo "[4/4] enterprise readiness artifact"
        test -f ./enterprise-readiness-report.json

        echo "All full-app checks passed."
        """
    }

    private func makeBuildManifest(
        target: StudioViewModel.BuildTarget,
        deterministicHash: String,
        context: BuildContext,
        generatedAt: Date
    ) -> BuildManifest {
        BuildManifest(
            schemaVersion: 4,
            projectName: context.projectName,
            projectID: context.projectID,
            target: target.rawValue,
            generatedAt: generatedAt,
            deterministicHash: deterministicHash,
            appType: context.latestScope?.appType,
            productIntent: context.latestScope?.productIntent,
            capabilities: context.latestScope?.keyCapabilities ?? [],
            mirrorScore: context.latestBlueprint?.mirrorScore,
            inferredControls: context.latestBlueprint?.controls ?? [],
            inferredStates: context.latestBlueprint?.states ?? [],
            suggestedStateArtboards: context.latestBlueprint?.suggestedArtboards ?? [],
            designTokens: context.latestDesignTokens,
            tokenRevisions: context.tokenRevisions,
            componentSpecs: context.latestComponentSpecs,
            componentInstances: context.componentInstances,
            strategySpec: context.acceptedStrategySpec,
            importLossReport: context.importLossReport,
            reviewComments: context.reviewComments,
            reviewApprovalState: context.reviewApprovalState,
            benchmarkReport: context.latestBenchmarkReport,
            benchmarkHistoryCount: context.benchmarkHistory.count,
            benchmarkTrendScore: context.benchmarkTrendScore,
            pipelineMode: context.pipelineMode.rawValue,
            stylePreset: context.mockupStylePreset.rawValue,
            activeArtboardName: context.document.artboard.name,
            artboardCount: context.artboards.count,
            elementCount: context.document.artboard.elements.count,
            memorySnapshotCount: context.memorySnapshotCount,
            analysisDocument: context.document
        )
    }

    private func computeDeterministicHash(
        target: StudioViewModel.BuildTarget,
        context: BuildContext
    ) -> String {
        struct DeterministicPayload: Codable {
            var projectName: String
            var projectID: String
            var target: String
            var pipelineMode: String
            var stylePreset: String
            var artboards: [Artboard]
            var scope: ProductScopeSnapshot?
            var blueprint: BuildBlueprint?
            var tokens: DesignTokenSet?
            var components: [ComponentSpec]
            var analysisDocument: AnalysisDocument
        }

        var normalizedDocument = context.document
        normalizedDocument.metadata.generatedAt = Date(timeIntervalSince1970: 0)

        let payload = DeterministicPayload(
            projectName: context.projectName,
            projectID: context.projectID,
            target: target.rawValue,
            pipelineMode: context.pipelineMode.rawValue,
            stylePreset: context.mockupStylePreset.rawValue,
            artboards: context.artboards,
            scope: context.latestScope,
            blueprint: context.latestBlueprint,
            tokens: context.latestDesignTokens,
            components: context.latestComponentSpecs,
            analysisDocument: normalizedDocument
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(payload)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func writeBenchmarkTrendArtifact(
        target: StudioViewModel.BuildTarget,
        outputDirectory: URL,
        deterministicHash: String,
        generatedAt: Date,
        encoder: JSONEncoder,
        context: BuildContext
    ) throws {
        let artifact = BenchmarkTrendArtifact(
            generatedAt: generatedAt,
            projectName: context.projectName,
            projectID: context.projectID,
            target: target.rawValue,
            deterministicHash: deterministicHash,
            latestBenchmarkReport: context.latestBenchmarkReport,
            trendScore: context.benchmarkTrendScore,
            history: Array(context.benchmarkHistory.suffix(24))
        )
        let data = try encoder.encode(artifact)
        let url = outputDirectory.appendingPathComponent("benchmark-trend-report.json")
        try data.write(to: url, options: .atomic)
    }

    private func runSmokeChecks(
        for target: StudioViewModel.BuildTarget,
        in outputDirectory: URL
    ) -> [SmokeCheckResult] {
        var checks: [(title: String, command: String)] = [
            ("Manifest exists", "test -f ./build-manifest.json"),
            ("Checklist exists", "test -f ./scaffold-todo.md"),
            ("Benchmark trend report exists", "test -f ./benchmark-trend-report.json"),
            ("Full app directory exists", "test -d ./full-app"),
        ]

        switch target {
        case .ios:
            checks.append(("iOS scaffold file exists", "test -f ./scaffold/ios-swiftui/GeneratedDashboardView.swift"))
            checks.append(("iOS scaffold contains view", "grep -q \"GeneratedDashboardView\" ./scaffold/ios-swiftui/GeneratedDashboardView.swift"))
            checks.append(("iOS full app entry exists", "test -f ./full-app/ios-swiftui/Sources/GeneratedApp/GeneratedApp.swift"))
            checks.append(("iOS full app view exists", "test -f ./full-app/ios-swiftui/Sources/GeneratedApp/GeneratedDashboardView.swift"))
            checks.append(("iOS full app project spec exists", "test -f ./full-app/ios-swiftui/project.yml"))
            checks.append(("iOS full app spec exists", "test -f ./full-app/ios-swiftui/app-spec.json"))
            checks.append(("iOS full app spec json valid", "if command -v python3 >/dev/null; then python3 -c \"import json;json.load(open('./full-app/ios-swiftui/app-spec.json'))\"; else grep -q '\"states\"' ./full-app/ios-swiftui/app-spec.json; fi"))
            checks.append(("iOS full app xcodegen check", "if command -v xcodegen >/dev/null; then cd ./full-app/ios-swiftui && xcodegen generate >/dev/null; else test -f ./full-app/ios-swiftui/project.yml; fi"))
        case .macos:
            checks.append(("macOS scaffold file exists", "test -f ./scaffold/macos-swiftui/GeneratedDashboardView.swift"))
            checks.append(("macOS scaffold contains view", "grep -q \"GeneratedDashboardView\" ./scaffold/macos-swiftui/GeneratedDashboardView.swift"))
            checks.append(("macOS full app package exists", "test -f ./full-app/macos-swiftui/Package.swift"))
            checks.append(("macOS full app entry exists", "test -f ./full-app/macos-swiftui/Sources/GeneratedApp/GeneratedApp.swift"))
            checks.append(("macOS full app spec exists", "test -f ./full-app/macos-swiftui/app-spec.json"))
            checks.append(("macOS full app spec json valid", "if command -v python3 >/dev/null; then python3 -c \"import json;json.load(open('./full-app/macos-swiftui/app-spec.json'))\"; else grep -q '\"states\"' ./full-app/macos-swiftui/app-spec.json; fi"))
            checks.append(("macOS full app builds", "cd ./full-app/macos-swiftui && swift build"))
        case .web:
            checks.append(("Web scaffold files exist", "test -f ./scaffold/web/index.html && test -f ./scaffold/web/styles.css && test -f ./scaffold/web/app.js"))
            checks.append(("Web scaffold contains blueprint log", "grep -Eq \"Generated (scaffold|full app) blueprint\" ./scaffold/web/app.js"))
            checks.append(("Web full app files exist", "test -f ./full-app/web/index.html && test -f ./full-app/web/styles.css && test -f ./full-app/web/app.js"))
            checks.append(("Web full app spec exists", "test -f ./full-app/web/app-spec.json"))
            checks.append(("Web full app spec json valid", "if command -v python3 >/dev/null; then python3 -c \"import json;json.load(open('./full-app/web/app-spec.json'))\"; else grep -q '\"states\"' ./full-app/web/app-spec.json; fi"))
            checks.append(("Web full app script syntax", "if command -v node >/dev/null; then node --check ./full-app/web/app.js; else grep -Eq \"Generated (scaffold|full app) blueprint\" ./full-app/web/app.js; fi"))
        }

        return checks.map { check in
            let execution = executeShellCommand(check.command, currentDirectory: outputDirectory)
            let summary = execution.output.isEmpty ? check.title : execution.output
            return SmokeCheckResult(
                id: deterministicUUID(seed: "smoke|\(target.rawValue)|\(check.title)|\(check.command)"),
                name: check.title,
                target: target.rawValue,
                command: check.command,
                passed: execution.exitCode == 0,
                output: summary
            )
        }
    }

    private func deterministicUUID(seed: String) -> UUID {
        ScaffoldGenerator.deterministicUUID(seed: seed)
    }

    private func executeShellCommand(_ command: String, currentDirectory: URL) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData + errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - BuildContext Helpers

extension BuildExportService.BuildContext {
    /// Returns a copy of the context with all dates set to referenceDate.
    /// Used when producing deterministic snapshots.
    func withReferenceDate(_ date: Date) -> BuildExportService.BuildContext {
        var doc = self.document
        doc.metadata.generatedAt = date
        var copy = self
        copy.document = doc
        return copy
    }
}

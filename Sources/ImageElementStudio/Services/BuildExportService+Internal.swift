import CryptoKit
import Foundation

// MARK: - BuildExportService Internal Helpers

extension BuildExportService {

    // MARK: - Quality Gate Summary

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
            smokePassRate = Constants.QualityGate.defaultNoDataRate
        } else {
            let passCount = smokeChecks.filter(\.passed).count
            smokePassRate = Double(passCount) / Double(smokeChecks.count)
        }

        let fullAppChecks = smokeChecks.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains("full app")
        }
        let fullAppPassRate: Double
        if fullAppChecks.isEmpty {
            fullAppPassRate = Constants.QualityGate.defaultNoDataRate
        } else {
            let passCount = fullAppChecks.filter(\.passed).count
            fullAppPassRate = Double(passCount) / Double(fullAppChecks.count)
        }

        let diffHealthScore: Double
        if diffEntries.isEmpty {
            diffHealthScore = Constants.QualityGate.defaultNoDataRate
        } else {
            let averageImpact = diffEntries.map(\.impactScore).reduce(0, +) / Double(diffEntries.count)
            diffHealthScore = max(0, 1 - min(1, averageImpact))
        }

        let normalizedBenchmarkPassRate = max(0, min(1, benchmarkPassRate ?? Constants.QualityGate.defaultNoDataRate))
        let smokePoints = smokePassRate * Constants.QualityGate.smokeCheckMaxPoints
        let fullAppPoints = fullAppPassRate * Constants.QualityGate.fullAppMaxPoints
        let diffPoints = diffHealthScore * Constants.QualityGate.diffHealthMaxPoints
        let benchmarkPoints = normalizedBenchmarkPassRate * Constants.QualityGate.benchmarkMaxPoints
        let reviewPoints = reviewGatePassed ? Constants.QualityGate.reviewGatePoints : 0.0
        let overduePenalty = min(Double(overdueCommentCount) * Constants.QualityGate.overdueCommentPenalty, Constants.QualityGate.maxOverduePenalty)
        let totalScore = max(
            0,
            min(100, smokePoints + fullAppPoints + diffPoints + benchmarkPoints + reviewPoints - overduePenalty)
        )

        let status: QualityGateStatus
        switch totalScore {
        case Constants.QualityGate.passScoreThreshold...:
            status = .pass
        case Constants.QualityGate.warningScoreThreshold..<Constants.QualityGate.passScoreThreshold:
            status = .warning
        default:
            status = .fail
        }

        var issues: [String] = []
        if smokeChecks.isEmpty {
            issues.append("No smoke checks captured yet.")
        } else if smokePassRate < Constants.QualityGate.smokePassRateThreshold {
            issues.append("Smoke-check pass rate below 90%.")
        }
        if fullAppChecks.isEmpty {
            issues.append("No full-app smoke checks captured yet.")
        } else if fullAppPassRate < Constants.QualityGate.fullAppPassRateThreshold {
            issues.append("Full-app smoke checks below 90%.")
        }
        if diffEntries.isEmpty {
            issues.append("No design/code diff artifacts available.")
        } else if diffEntries.contains(where: { $0.impactScore >= Constants.QualityGate.highImpactDiffThreshold }) {
            issues.append("High-impact design/code drifts detected.")
        }
        if normalizedBenchmarkPassRate < Constants.QualityGate.benchmarkPassRateWarningThreshold {
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
        let highImpactDiffs = context.designCodeDiffs.contains { $0.impactScore >= Constants.QualityGate.highImpactDiffThreshold }
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
                passed: summary.aggregateScore >= Constants.Enterprise.passScoreThreshold,
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
                passed: benchmarkPassRate >= Constants.Enterprise.benchmarkPassRateThreshold,
                detail: "Current benchmark trend pass-rate: \(Int((benchmarkPassRate * 100).rounded()))%."
            ),
            EnterpriseReadinessCheck(
                id: deterministicUUID(seed: "enterprise|\(summary.runID.uuidString)|interop"),
                name: "Import cleanup estimate <= 20%",
                weight: 10,
                passed: importCleanupPercent <= Constants.Enterprise.maxImportCleanupPercent,
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
        if score >= Constants.Enterprise.passScoreThreshold && blockers.isEmpty {
            status = .pass
        } else if score >= Constants.Enterprise.warningScoreThreshold {
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

    // MARK: - Utility

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

    // MARK: - Build Output Directories

    func makeFullStackBuildOutputDirectory(projectName: String) throws -> URL {
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

    func makeBuildOutputDirectory(
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

    // MARK: - Smoke Checks & Validation

    func fullAppSmokePassRate(in checks: [SmokeCheckResult]) -> Double {
        let fullAppChecks = checks.filter { check in
            (check.name ?? "").localizedCaseInsensitiveContains("full app")
        }
        guard !fullAppChecks.isEmpty else { return 0 }
        let passCount = fullAppChecks.filter(\.passed).count
        return Double(passCount) / Double(fullAppChecks.count)
    }

    func fullStackValidationScript() -> String {
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

    // MARK: - Build Manifest

    func makeBuildManifest(
        target: StudioViewModel.BuildTarget,
        deterministicHash: String,
        context: BuildContext,
        generatedAt: Date
    ) -> BuildManifest {
        BuildManifest(
            schemaVersion: Constants.BuildManifest.schemaVersion,
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

    // MARK: - Deterministic Hashing

    func computeDeterministicHash(
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
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            // Encoding failure means the hash will be based on empty data, which is
            // detectable downstream. Log so the root cause is not silently lost.
            AppLogger.error("Deterministic hash encoding failed: \(error.localizedDescription)", category: .export)
            data = Data()
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Benchmark Trend Artifact

    func writeBenchmarkTrendArtifact(
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
            history: Array(context.benchmarkHistory.suffix(Constants.Benchmark.trendArtifactHistoryCount))
        )
        let data = try encoder.encode(artifact)
        let url = outputDirectory.appendingPathComponent("benchmark-trend-report.json")
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Smoke Checks

    func runSmokeChecks(
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

    // MARK: - Deterministic UUID

    func deterministicUUID(seed: String) -> UUID {
        ScaffoldGenerator.deterministicUUID(seed: seed)
    }

    // MARK: - Shell Execution

    func executeShellCommand(_ command: String, currentDirectory: URL) -> (exitCode: Int32, output: String) {
        #if !APP_STORE
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
        #else
        return (exitCode: 1, output: "[App Store build] Shell execution is not available in this edition.")
        #endif
    }

    // MARK: - Encoder

    func makeEncoder() -> JSONEncoder {
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

    /// Convenience initializer that snapshots a StudioViewModel.
    @MainActor init(from vm: StudioViewModel) {
        self.init(
            projectName: vm.projectName, projectID: vm.memory.projectID ?? vm.buildExportService.slugified(vm.projectName),
            pipelineMode: vm.pipelineMode, mockupStylePreset: vm.mockupStylePreset, artboards: vm.artboards,
            latestScope: vm.latestScope, latestBlueprint: vm.latestBlueprint, latestDesignTokens: vm.latestDesignTokens,
            tokenRevisions: vm.tokenRevisions, latestComponentSpecs: vm.latestComponentSpecs, componentInstances: vm.componentInstances,
            acceptedStrategySpec: vm.acceptedStrategySpec, importLossReport: vm.importLossReport,
            reviewComments: vm.reviewComments, reviewApprovalState: vm.reviewApprovalState.rawValue,
            latestBenchmarkReport: vm.latestBenchmarkReport, benchmarkHistory: vm.benchmarkHistory,
            benchmarkTrendScore: vm.benchmarkTrendScore, designCodeDiffs: vm.designCodeDiffs,
            latestBuildQualityReport: vm.latestBuildQualityReport, canExportBuildArtifacts: vm.canExportBuildArtifacts,
            reviewGateBlockReason: vm.reviewGateBlockReason, reviewGateStatusLine: vm.reviewGateStatusLine,
            overdueReviewCommentCount: vm.overdueReviewCommentCount, unresolvedReviewCommentCount: vm.unresolvedReviewCommentCount,
            qualityGateScoreLine: vm.qualityGateScoreLine, memorySnapshotCount: vm.memory.entries.count,
            memoryEntryCount: vm.memory.entries.count, activeArtboard: vm.activeArtboard, document: vm.currentDocument(),
            strategySessionStage: vm.strategySession?.stage.rawValue, acceptedStrategySpecConfidence: vm.acceptedStrategySpec?.confidence
        )
    }
}

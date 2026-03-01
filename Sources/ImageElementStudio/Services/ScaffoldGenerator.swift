import CryptoKit
import Foundation

/// Pure scaffold and template code generation extracted from StudioViewModel.
/// All methods are static and take model types as parameters, returning generated strings
/// or writing files to disk.
enum ScaffoldGenerator {

    // MARK: - Deterministic UUID

    static func deterministicUUID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let tuple = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }

    // MARK: - Build Quality Report Loading

    static func loadBuildQualityReport(from outputDirectory: URL, decoder: JSONDecoder) throws -> BuildQualityReport {
        let url = outputDirectory.appendingPathComponent("build-quality-report.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(BuildQualityReport.self, from: data)
    }

    // MARK: - Scaffold File Path

    static func scaffoldFilePath(for target: StudioViewModel.BuildTarget) -> String {
        switch target {
        case .ios:
            return "full-app/ios-swiftui/Sources/GeneratedApp/GeneratedDashboardView.swift"
        case .macos:
            return "full-app/macos-swiftui/Sources/GeneratedApp/GeneratedDashboardView.swift"
        case .web:
            return "full-app/web/index.html"
        }
    }

    // MARK: - Readme & Checklist

    static func buildReadme(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest,
        qualityGateScoreLine: String
    ) -> String {
        let scope = manifest.appType ?? "Unclassified product"
        let mirror = manifest.mirrorScore.map { "\(Int(($0 * 100).rounded()))%" } ?? "N/A"
        return """
        # \(manifest.projectName) - \(target.title) Build Setup

        Generated: \(manifest.generatedAt.formatted(date: .abbreviated, time: .shortened))

        ## Confirmed Context
        - Target: \(target.title) (\(target.buildLabel))
        - App Type: \(scope)
        - Active Artboard: \(manifest.activeArtboardName)
        - Elements: \(manifest.elementCount)
        - Mirror Score: \(mirror)
        - Inferred Controls: \(manifest.inferredControls.count)
        - Inferred States: \(manifest.inferredStates.count)
        - Design Tokens: \(manifest.designTokens?.colors.count ?? 0) colors
        - Token Revisions: \(manifest.tokenRevisions.count)
        - Component Specs: \(manifest.componentSpecs.count)
        - Component Instances: \(manifest.componentInstances.count)
        - Import Cleanup Estimate: \(Int((manifest.importLossReport?.estimatedManualCleanupPercent ?? 0).rounded()))%
        - Review State: \(manifest.reviewApprovalState)
        - Benchmark: \(manifest.benchmarkReport?.passed == true ? "pass" : "not passed")
        - Benchmark History Entries: \(manifest.benchmarkHistoryCount)
        - Benchmark Trend Pass Rate: \(Int(((manifest.benchmarkTrendScore?.passRate ?? 0) * 100).rounded()))%
        - Benchmark Trend Median Latency: \(Int((manifest.benchmarkTrendScore?.medianStepLatencyMilliseconds ?? 0).rounded()))ms
        - Quality Gate: \(qualityGateScoreLine)
        - Pipeline Mode: \(manifest.pipelineMode)
        - Style Preset: \(manifest.stylePreset)
        - Deterministic Hash: \(manifest.deterministicHash)
        - Memory Snapshots: \(manifest.memorySnapshotCount)

        ## Included Files
        - `build-manifest.json`: full semantic + layout payload
        - `build-quality-report.json`: deterministic hash + smoke checks + diff artifacts
        - `benchmark-trend-report.json`: benchmark pass-rate/latency trend history
        - `scaffold-todo.md`: next implementation checklist
        - `scaffold/`: generated starter files for \(target.title)
        - `full-app/`: runnable app output for \(target.title)
        """
    }

    static func buildScaffoldChecklist(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest
    ) -> String {
        let firstCapabilities = manifest.capabilities.prefix(4)
        let capabilityList = firstCapabilities.isEmpty
            ? "- Define initial core capabilities from semantic map."
            : firstCapabilities.map { "- \($0)" }.joined(separator: "\n")

        return """
        # Scaffold Checklist (\(target.title))

        1. Create project shell for \(target.buildLabel.lowercased()).
        2. Build layout skeleton from active artboard geometry.
        3. Map semantic elements into reusable UI components.
        4. Bind capabilities:
        \(capabilityList)
        5. Implement inferred states (\(manifest.inferredStates.count)) and transitions from control actions.
        6. Connect data models and state for listed UI sections.
        7. Run first smoke build and iterate.
        """
    }

    // MARK: - Design Code Diff Entries

    static func buildDesignCodeDiffEntries(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest,
        outputDirectory: URL
    ) -> [DesignCodeDiffEntry] {
        let filePath = scaffoldFilePath(for: target)
        let fileURL = outputDirectory.appendingPathComponent(filePath)
        // Best-effort: scaffold file may not exist yet; empty content triggers expected diff entries.
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return buildDesignCodeDiffEntries(for: target, manifest: manifest, scaffoldContent: content, filePath: filePath)
    }

    static func buildDesignCodeDiffEntries(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest,
        scaffoldContent content: String,
        filePath: String
    ) -> [DesignCodeDiffEntry] {
        var diffs: [DesignCodeDiffEntry] = []

        for state in manifest.inferredStates.prefix(10) where !content.localizedCaseInsensitiveContains(state.name) {
            let detail = "State '\(state.name)' was inferred from design but not emitted into \(filePath)."
            diffs.append(
                DesignCodeDiffEntry(
                    id: deterministicUUID(seed: "diff|\(target.rawValue)|state|\(state.name)|\(filePath)"),
                    category: "state",
                    title: "Missing inferred state in scaffold",
                    detail: detail,
                    impactScore: 0.72
                )
            )
        }

        for control in manifest.inferredControls.prefix(10) where !content.localizedCaseInsensitiveContains(control.label) {
            let detail = "Control '\(control.label)' is not represented in \(filePath)."
            diffs.append(
                DesignCodeDiffEntry(
                    id: deterministicUUID(seed: "diff|\(target.rawValue)|control|\(control.label)|\(filePath)"),
                    category: "control",
                    title: "Missing inferred control label in scaffold",
                    detail: detail,
                    impactScore: 0.55
                )
            )
        }

        if !manifest.componentSpecs.isEmpty && !content.localizedCaseInsensitiveContains("component") {
            let detail = "Generated file lacks explicit component references despite \(manifest.componentSpecs.count) inferred component specs."
            diffs.append(
                DesignCodeDiffEntry(
                    id: deterministicUUID(seed: "diff|\(target.rawValue)|component|\(manifest.componentSpecs.count)|\(filePath)"),
                    category: "component",
                    title: "Component metadata not reflected in scaffold",
                    detail: detail,
                    impactScore: 0.63
                )
            )
        }

        if let tokenCount = manifest.designTokens?.colors.count, tokenCount > 0, !content.localizedCaseInsensitiveContains("token") {
            let detail = "Detected \(tokenCount) color tokens but scaffold file has no token mapping markers."
            diffs.append(
                DesignCodeDiffEntry(
                    id: deterministicUUID(seed: "diff|\(target.rawValue)|tokens|\(tokenCount)|\(filePath)"),
                    category: "tokens",
                    title: "Token set not explicitly mapped",
                    detail: detail,
                    impactScore: 0.49
                )
            )
        }

        if diffs.isEmpty {
            diffs.append(
                DesignCodeDiffEntry(
                    id: deterministicUUID(seed: "diff|\(target.rawValue)|summary|\(filePath)"),
                    category: "summary",
                    title: "No major scaffold drift detected",
                    detail: "Basic state/control coverage is present for target \(target.title).",
                    impactScore: 0.08
                )
            )
        }

        return diffs
    }

    // MARK: - Write Generated Scaffold

    static func writeGeneratedScaffold(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest,
        to outputDirectory: URL
    ) throws {
        let scaffoldRoot = outputDirectory.appendingPathComponent("scaffold", isDirectory: true)
        try FileManager.default.createDirectory(at: scaffoldRoot, withIntermediateDirectories: true)

        switch target {
        case .ios:
            let folder = scaffoldRoot.appendingPathComponent("ios-swiftui", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeString(
                generatedScaffoldSpec(for: target, manifest: manifest),
                to: folder.appendingPathComponent("README.md")
            )
            try writeString(
                generatedIOSSwiftUIView(manifest: manifest),
                to: folder.appendingPathComponent("GeneratedDashboardView.swift")
            )

        case .macos:
            let folder = scaffoldRoot.appendingPathComponent("macos-swiftui", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeString(
                generatedScaffoldSpec(for: target, manifest: manifest),
                to: folder.appendingPathComponent("README.md")
            )
            try writeString(
                generatedMacOSSwiftUIView(manifest: manifest),
                to: folder.appendingPathComponent("GeneratedDashboardView.swift")
            )

        case .web:
            let folder = scaffoldRoot.appendingPathComponent("web", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeString(
                generatedScaffoldSpec(for: target, manifest: manifest),
                to: folder.appendingPathComponent("README.md")
            )
            try writeString(
                generatedWebHTML(manifest: manifest),
                to: folder.appendingPathComponent("index.html")
            )
            try writeString(
                generatedWebCSS(),
                to: folder.appendingPathComponent("styles.css")
            )
            try writeString(
                generatedWebJS(manifest: manifest),
                to: folder.appendingPathComponent("app.js")
            )
        }
    }

    // MARK: - Write Generated Full App

    static func writeGeneratedFullApp(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest,
        deterministicHash: String,
        generatedAt: Date,
        encoder: JSONEncoder,
        to outputDirectory: URL
    ) throws {
        let root = outputDirectory.appendingPathComponent("full-app", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let appSpec = generatedAppSpec(
            manifest: manifest,
            target: target,
            deterministicHash: deterministicHash,
            generatedAt: generatedAt
        )
        let appSpecData = try encoder.encode(appSpec)

        switch target {
        case .ios:
            let folder = root.appendingPathComponent("ios-swiftui", isDirectory: true)
            let sources = folder.appendingPathComponent("Sources/GeneratedApp", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try writeString(generatedIOSFullAppReadme(manifest: manifest), to: folder.appendingPathComponent("README.md"))
            try writeString(generatedIOSProjectYAML(), to: folder.appendingPathComponent("project.yml"))
            try writeString(generatedIOSFullAppEntry(), to: sources.appendingPathComponent("GeneratedApp.swift"))
            try writeString(generatedIOSSwiftUIView(manifest: manifest, appSpec: appSpec), to: sources.appendingPathComponent("GeneratedDashboardView.swift"))
            try appSpecData.write(to: folder.appendingPathComponent("app-spec.json"), options: .atomic)

        case .macos:
            let folder = root.appendingPathComponent("macos-swiftui", isDirectory: true)
            let sources = folder.appendingPathComponent("Sources/GeneratedApp", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try writeString(generatedMacOSFullAppPackage(), to: folder.appendingPathComponent("Package.swift"))
            try writeString(generatedMacOSFullAppEntry(), to: sources.appendingPathComponent("GeneratedApp.swift"))
            try writeString(generatedMacOSSwiftUIView(manifest: manifest, appSpec: appSpec), to: sources.appendingPathComponent("GeneratedDashboardView.swift"))
            try writeString(generatedMacOSFullAppReadme(manifest: manifest), to: folder.appendingPathComponent("README.md"))
            try appSpecData.write(to: folder.appendingPathComponent("app-spec.json"), options: .atomic)

        case .web:
            let folder = root.appendingPathComponent("web", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeString(generatedWebHTML(manifest: manifest), to: folder.appendingPathComponent("index.html"))
            try writeString(generatedWebCSS(), to: folder.appendingPathComponent("styles.css"))
            try writeString(generatedWebJS(appSpec: appSpec), to: folder.appendingPathComponent("app.js"))
            try writeString(generatedWebFullAppReadme(manifest: manifest), to: folder.appendingPathComponent("README.md"))
            try appSpecData.write(to: folder.appendingPathComponent("app-spec.json"), options: .atomic)
        }
    }

    // MARK: - Generated App Spec

    static func generatedAppSpec(
        manifest: StudioViewModel.BuildManifest,
        target: StudioViewModel.BuildTarget,
        deterministicHash: String,
        generatedAt: Date
    ) -> GeneratedAppSpec {
        let states = normalizedStateNames(from: manifest)
        let controls = normalizedControlLabels(from: manifest)
        let capabilities = normalizedCapabilities(from: manifest)
        let screens = inferredScreens(manifest: manifest, states: states, capabilities: capabilities)
        let transitions = inferredTransitions(states: states, controls: controls)

        return GeneratedAppSpec(
            generatedAt: generatedAt,
            projectName: manifest.projectName,
            projectID: manifest.projectID,
            target: target.rawValue,
            deterministicHash: deterministicHash,
            appType: manifest.appType,
            productIntent: manifest.productIntent,
            initialState: states.first ?? "Default",
            states: states,
            controls: controls,
            capabilities: capabilities,
            screens: screens,
            transitions: transitions
        )
    }

    // MARK: - Scaffold Spec (README)

    static func generatedScaffoldSpec(
        for target: StudioViewModel.BuildTarget,
        manifest: StudioViewModel.BuildManifest
    ) -> String {
        let mirror = manifest.mirrorScore.map { "\(Int(($0 * 100).rounded()))%" } ?? "N/A"
        let capabilities = markdownList(manifest.capabilities, fallback: "Define product capabilities from image semantics.")
        let states = markdownList(manifest.inferredStates.map(\.name), fallback: "Default View")
        let controls = markdownList(manifest.inferredControls.map(\.label), fallback: "No controls inferred.")
        let components = markdownList(manifest.componentSpecs.map(\.name), fallback: "No component specs inferred.")
        let tokenCount = manifest.designTokens?.colors.count ?? 0

        return """
        # Generated Scaffold - \(target.title)

        This scaffold was generated from one uploaded design image.

        ## Context
        - Project: \(manifest.projectName)
        - App type: \(manifest.appType ?? "Unclassified")
        - Artboard: \(manifest.activeArtboardName)
        - Mirror score: \(mirror)
        - Deterministic hash: \(manifest.deterministicHash)
        - Elements: \(manifest.elementCount)
        - Design token colors: \(tokenCount)

        ## Inferred Controls
        \(controls)

        ## Inferred States
        \(states)

        ## Component Specs
        \(components)

        ## Inferred Capabilities
        \(capabilities)
        """
    }

    // MARK: - File Writing

    static func writeString(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

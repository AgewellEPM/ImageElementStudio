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

    // MARK: - macOS Full App Templates

    static func generatedMacOSFullAppPackage() -> String {
        """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "GeneratedApp",
            platforms: [
                .macOS(.v14),
            ],
            products: [
                .executable(name: "GeneratedApp", targets: ["GeneratedApp"]),
            ],
            targets: [
                .executableTarget(name: "GeneratedApp"),
            ]
        )
        """
    }

    static func generatedMacOSFullAppEntry() -> String {
        """
        import SwiftUI

        @main
        struct GeneratedApp: App {
            var body: some Scene {
                WindowGroup {
                    GeneratedDashboardView()
                }
            }
        }
        """
    }

    static func generatedMacOSFullAppReadme(manifest: StudioViewModel.BuildManifest) -> String {
        """
        # Generated macOS App

        This is a runnable macOS SwiftUI app generated from screenshot + conversation context.

        ## Run
        ```bash
        cd ./full-app/macos-swiftui
        swift run
        ```

        ## Context
        - Project: \(manifest.projectName)
        - App Type: \(manifest.appType ?? "Unclassified")
        - Controls: \(manifest.inferredControls.count)
        - States: \(manifest.inferredStates.count)
        """
    }

    // MARK: - iOS Full App Templates

    static func generatedIOSFullAppEntry() -> String {
        """
        import SwiftUI

        @main
        struct GeneratedApp: App {
            var body: some Scene {
                WindowGroup {
                    GeneratedDashboardView()
                }
            }
        }
        """
    }

    static func generatedIOSProjectYAML() -> String {
        """
        name: GeneratedApp
        options:
          bundleIdPrefix: com.imageelementstudio
          deploymentTarget:
            iOS: "17.0"
        targets:
          GeneratedApp:
            type: application
            platform: iOS
            sources:
              - Sources/GeneratedApp
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: com.imageelementstudio.generated
                SWIFT_VERSION: 5.9
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        """
    }

    static func generatedIOSFullAppReadme(manifest: StudioViewModel.BuildManifest) -> String {
        """
        # Generated iOS SwiftUI App

        Generated from screenshot + conversation context.

        ## Build
        1. Install `xcodegen` if needed.
        2. Run:
           ```bash
           cd ./full-app/ios-swiftui
           xcodegen generate
           open GeneratedApp.xcodeproj
           ```
        3. Build/run in Xcode simulator.

        ## Context
        - Project: \(manifest.projectName)
        - App Type: \(manifest.appType ?? "Unclassified")
        - Controls: \(manifest.inferredControls.count)
        - States: \(manifest.inferredStates.count)
        """
    }

    // MARK: - Web Full App Templates

    static func generatedWebFullAppReadme(manifest: StudioViewModel.BuildManifest) -> String {
        """
        # Generated Web App

        Generated from screenshot + conversation context.

        ## Run
        Open `index.html` directly or serve folder:

        ```bash
        cd ./full-app/web
        python3 -m http.server 8080
        ```

        ## Context
        - Project: \(manifest.projectName)
        - App Type: \(manifest.appType ?? "Unclassified")
        - Controls: \(manifest.inferredControls.count)
        - States: \(manifest.inferredStates.count)
        """
    }

    // MARK: - iOS SwiftUI View

    static func generatedIOSSwiftUIView(manifest: StudioViewModel.BuildManifest) -> String {
        let appSpec = generatedAppSpec(
            manifest: manifest,
            target: .ios,
            deterministicHash: manifest.deterministicHash,
            generatedAt: manifest.generatedAt
        )
        return generatedIOSSwiftUIView(manifest: manifest, appSpec: appSpec)
    }

    static func generatedIOSSwiftUIView(manifest: StudioViewModel.BuildManifest, appSpec: GeneratedAppSpec) -> String {
        let title = escapedSwiftString(appSpec.appType ?? appSpec.projectName)
        let subtitle = escapedSwiftString(appSpec.productIntent ?? "Generated from screenshot and strategy conversation.")
        let defaultState = escapedSwiftString(appSpec.initialState)
        let statesLiteral = swiftStringArrayLiteral(appSpec.states)
        let controlsLiteral = swiftStringArrayLiteral(appSpec.controls)
        let capabilitiesLiteral = swiftStringArrayLiteral(appSpec.capabilities)
        let transitionPairs = appSpec.transitions.map { ($0.controlLabel, $0.toState) }
        let transitionsLiteral = swiftStringDictionaryLiteral(transitionPairs)
        let screensLiteral = swiftGeneratedScreenArrayLiteral(appSpec.screens)
        let defaultScreenID = appSpec.screens.first?.id.uuidString ?? deterministicUUID(seed: "fallback-screen|\(appSpec.projectID)").uuidString

        return """
        import SwiftUI

        struct GeneratedDashboardView: View {
            @State private var selectedState: String = "\(defaultState)"
            @State private var selectedScreenID: String? = "\(defaultScreenID)"
            @State private var actionLog: [String] = []
            private let inferredStates: [String] = \(statesLiteral)
            private let inferredControls: [String] = \(controlsLiteral)
            private let inferredCapabilities: [String] = \(capabilitiesLiteral)
            private let inferredTransitions: [String: String] = \(transitionsLiteral)
            private let generatedScreens: [GeneratedScreen] = \(screensLiteral)

            var body: some View {
                NavigationSplitView {
                    List(generatedScreens, selection: $selectedScreenID) { screen in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(screen.name)
                            Text(screen.state)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(screen.id)
                    }
                    .navigationTitle("Screens")
                    .frame(minWidth: 220)
                } detail: {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(title)")
                            .font(.title2.weight(.semibold))
                        Text("\(subtitle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let activeScreen = activeScreen {
                            GroupBox("Current Screen") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(activeScreen.name)
                                        .font(.headline)
                                    Text(activeScreen.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text("State: \\(activeScreen.state)")
                                        .font(.caption.monospaced())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                            }
                        }

                        Picker("State", selection: $selectedState) {
                            ForEach(inferredStates, id: \\.self) { state in
                                Text(state).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedState) { _, newValue in
                            selectBestScreen(for: newValue)
                        }

                        GroupBox("Capabilities") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                                ForEach(activeCapabilities, id: \\.self) { capability in
                                    Text(capability)
                                        .font(.footnote)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        GroupBox("Controls") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(inferredControls, id: \\.self) { control in
                                    Button(control) {
                                        trigger(control)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        GroupBox("Activity Log") {
                            if actionLog.isEmpty {
                                Text("No interactions yet. Tap a control to simulate flow.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(actionLog, id: \\.self) { line in
                                            Text(line)
                                                .font(.caption.monospaced())
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .frame(maxHeight: 140)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Generated App")
                }
            }

            private func trigger(_ control: String) {
                guard !inferredStates.isEmpty else { return }
                if let nextState = inferredTransitions[control] {
                    selectedState = nextState
                } else if let index = inferredStates.firstIndex(of: selectedState) {
                    selectedState = inferredStates[(index + 1) % inferredStates.count]
                } else {
                    selectedState = inferredStates[0]
                }
                let line = "\\(Date.now.formatted(date: .omitted, time: .shortened)) \u{2022} \\(control) -> \\(selectedState)"
                actionLog.insert(line, at: 0)
                if actionLog.count > 24 {
                    actionLog.removeLast(actionLog.count - 24)
                }
                selectBestScreen(for: selectedState)
            }

            private var activeScreen: GeneratedScreen? {
                if let selectedScreenID, let match = generatedScreens.first(where: { $0.id == selectedScreenID }) {
                    return match
                }
                return generatedScreens.first
            }

            private var activeCapabilities: [String] {
                guard let activeScreen, !activeScreen.capabilityHints.isEmpty else {
                    return inferredCapabilities
                }
                return activeScreen.capabilityHints
            }

            private func selectBestScreen(for state: String) {
                if let stateMatch = generatedScreens.first(where: { $0.state == state }) {
                    selectedScreenID = stateMatch.id
                    return
                }
                selectedScreenID = generatedScreens.first?.id
            }
        }

        private struct GeneratedScreen: Identifiable {
            var id: String
            var name: String
            var state: String
            var summary: String
            var capabilityHints: [String]
        }

        private extension GeneratedScreen {
            static let fallback = GeneratedScreen(
                id: "fallback",
                name: "Generated Screen",
                state: "Default",
                summary: "Fallback generated screen.",
                capabilityHints: []
            )
        }
        """
    }

    // MARK: - macOS SwiftUI View

    static func generatedMacOSSwiftUIView(manifest: StudioViewModel.BuildManifest) -> String {
        let appSpec = generatedAppSpec(
            manifest: manifest,
            target: .macos,
            deterministicHash: manifest.deterministicHash,
            generatedAt: manifest.generatedAt
        )
        return generatedMacOSSwiftUIView(manifest: manifest, appSpec: appSpec)
    }

    static func generatedMacOSSwiftUIView(manifest: StudioViewModel.BuildManifest, appSpec: GeneratedAppSpec) -> String {
        let title = escapedSwiftString(appSpec.appType ?? appSpec.projectName)
        let subtitle = escapedSwiftString(appSpec.productIntent ?? "Generated from screenshot and strategy conversation.")
        let defaultState = escapedSwiftString(appSpec.initialState)
        let statesLiteral = swiftStringArrayLiteral(appSpec.states)
        let controlsLiteral = swiftStringArrayLiteral(appSpec.controls)
        let capabilitiesLiteral = swiftStringArrayLiteral(appSpec.capabilities)
        let transitionsLiteral = swiftStringDictionaryLiteral(appSpec.transitions.map { ($0.controlLabel, $0.toState) })
        let screensLiteral = swiftGeneratedScreenArrayLiteral(appSpec.screens)
        let defaultScreenID = appSpec.screens.first?.id.uuidString ?? deterministicUUID(seed: "fallback-screen|\(appSpec.projectID)|macos").uuidString

        return """
        import SwiftUI

        struct GeneratedDashboardView: View {
            @State private var selectedState: String = "\(defaultState)"
            @State private var selectedScreenID: String? = "\(defaultScreenID)"
            @State private var actionLog: [String] = []
            private let inferredStates: [String] = \(statesLiteral)
            private let inferredControls: [String] = \(controlsLiteral)
            private let inferredCapabilities: [String] = \(capabilitiesLiteral)
            private let inferredTransitions: [String: String] = \(transitionsLiteral)
            private let generatedScreens: [GeneratedScreen] = \(screensLiteral)

            var body: some View {
                NavigationSplitView {
                    List(generatedScreens, selection: $selectedScreenID) { screen in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(screen.name)
                            Text(screen.state)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(screen.id)
                    }
                    .frame(minWidth: 240)
                } detail: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(title)")
                            .font(.title2.weight(.semibold))
                        Text("\(subtitle)")
                            .foregroundStyle(.secondary)

                        if let activeScreen = activeScreen {
                            GroupBox("Current Screen") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(activeScreen.name)
                                        .font(.headline)
                                    Text(activeScreen.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("State: \\(activeScreen.state)")
                                        .font(.caption.monospaced())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }

                        Picker("State", selection: $selectedState) {
                            ForEach(inferredStates, id: \\.self) { state in
                                Text(state).tag(state)
                            }
                        }
                        .onChange(of: selectedState) { _, newValue in
                            selectBestScreen(for: newValue)
                        }

                        GroupBox("Actions") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(inferredControls, id: \\.self) { control in
                                    Button {
                                        trigger(control)
                                    } label: {
                                        Label(control, systemImage: "bolt.fill")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        GroupBox("Capabilities") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(activeCapabilities, id: \\.self) { capability in
                                    Text("\u{2022} \\(capability)")
                                        .font(.subheadline)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        GroupBox("Activity Log") {
                            if actionLog.isEmpty {
                                Text("No interactions yet. Trigger actions from the left panel.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(actionLog, id: \\.self) { line in
                                            Text(line)
                                                .font(.caption.monospaced())
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .frame(maxHeight: 170)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
            }

            private func trigger(_ control: String) {
                guard !inferredStates.isEmpty else { return }
                if let nextState = inferredTransitions[control] {
                    selectedState = nextState
                } else if let index = inferredStates.firstIndex(of: selectedState) {
                    selectedState = inferredStates[(index + 1) % inferredStates.count]
                } else {
                    selectedState = inferredStates[0]
                }
                let line = "\\(Date.now.formatted(date: .omitted, time: .shortened)) \u{2022} \\(control) -> \\(selectedState)"
                actionLog.insert(line, at: 0)
                if actionLog.count > 30 {
                    actionLog.removeLast(actionLog.count - 30)
                }
                selectBestScreen(for: selectedState)
            }

            private var activeScreen: GeneratedScreen? {
                if let selectedScreenID, let match = generatedScreens.first(where: { $0.id == selectedScreenID }) {
                    return match
                }
                return generatedScreens.first
            }

            private var activeCapabilities: [String] {
                guard let activeScreen, !activeScreen.capabilityHints.isEmpty else {
                    return inferredCapabilities
                }
                return activeScreen.capabilityHints
            }

            private func selectBestScreen(for state: String) {
                if let stateMatch = generatedScreens.first(where: { $0.state == state }) {
                    selectedScreenID = stateMatch.id
                    return
                }
                selectedScreenID = generatedScreens.first?.id
            }
        }

        private struct GeneratedScreen: Identifiable {
            var id: String
            var name: String
            var state: String
            var summary: String
            var capabilityHints: [String]
        }

        private extension GeneratedScreen {
            static let fallback = GeneratedScreen(
                id: "fallback",
                name: "Generated Screen",
                state: "Default",
                summary: "Fallback generated screen.",
                capabilityHints: []
            )
        }
        """
    }

    // MARK: - Web HTML

    static func generatedWebHTML(manifest: StudioViewModel.BuildManifest) -> String {
        let title = escapedHTML(manifest.appType ?? manifest.projectName)
        let subtitle = escapedHTML(manifest.productIntent ?? "Generated from screenshot and strategy conversation.")

        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>\(title) - Generated Scaffold</title>
            <link rel="stylesheet" href="./styles.css" />
          </head>
          <body>
            <main class="app">
              <aside class="panel">
                <h2>Screens</h2>
                <ul id="screen-list" class="screen-list"></ul>
              </aside>

              <section class="workspace">
                <header>
                  <h1>\(title)</h1>
                  <p>\(subtitle)</p>
                  <div class="state-row">
                    <label for="state-select">State</label>
                    <select id="state-select"></select>
                    <span id="state-badge" class="state-badge"></span>
                  </div>
                </header>

                <section class="panel">
                  <h2>Current Screen</h2>
                  <p id="screen-summary" class="screen-summary"></p>
                </section>

                <section class="panel">
                  <h2>Capabilities</h2>
                  <div id="capability-grid" class="capability-grid"></div>
                </section>

                <section class="panel">
                  <h2>Controls</h2>
                  <div id="controls" class="controls"></div>
                </section>

                <section class="panel">
                  <h2>Activity</h2>
                  <ul id="activity-log" class="activity-log"></ul>
                </section>
              </section>
            </main>
            <script src="./app.js"></script>
          </body>
        </html>
        """
    }

    // MARK: - Web CSS

    static func generatedWebCSS() -> String {
        """
        :root {
          --bg: #0c111b;
          --panel: #182235;
          --panel-soft: #1f2b43;
          --text: #f6f8ff;
          --muted: #a6b1cb;
          --accent: #5ea1ff;
          --success: #2ec49d;
        }

        * { box-sizing: border-box; }
        body {
          margin: 0;
          background: radial-gradient(circle at top left, #16223a 0%, var(--bg) 55%);
          color: var(--text);
          font-family: "Avenir Next", "Segoe UI", sans-serif;
        }
        .app {
          max-width: 1180px;
          margin: 32px auto;
          padding: 24px;
          display: grid;
          grid-template-columns: 260px 1fr;
          gap: 12px;
          background: color-mix(in srgb, var(--panel) 88%, black);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 16px;
        }
        .workspace {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        header { margin-bottom: 16px; }
        h1, h2 { margin-top: 0; margin-bottom: 8px; }
        p { color: var(--muted); }
        .panel {
          background: var(--panel-soft);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 12px;
          padding: 14px;
          margin-bottom: 12px;
        }
        .state-row {
          display: flex;
          align-items: center;
          gap: 10px;
        }
        select {
          background: #0f1a2d;
          color: var(--text);
          border: 1px solid rgba(255, 255, 255, 0.22);
          border-radius: 8px;
          padding: 6px 8px;
        }
        .state-badge {
          background: color-mix(in srgb, var(--success) 60%, black);
          border-radius: 999px;
          padding: 4px 10px;
          font-size: 12px;
        }
        .screen-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }
        .screen-item {
          width: 100%;
          border: 1px solid rgba(255, 255, 255, 0.12);
          border-radius: 8px;
          background: rgba(255, 255, 255, 0.04);
          color: var(--text);
          text-align: left;
          padding: 8px 10px;
          cursor: pointer;
        }
        .screen-item.active {
          border-color: var(--accent);
          background: color-mix(in srgb, var(--accent) 18%, transparent);
        }
        .screen-summary {
          margin: 0;
          font-size: 14px;
          line-height: 1.4;
        }
        .capability-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
          gap: 8px;
        }
        .capability-card {
          background: rgba(255, 255, 255, 0.06);
          border-radius: 8px;
          padding: 10px;
          font-size: 14px;
        }
        .controls {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .control-btn {
          background: var(--accent);
          border: none;
          color: #041126;
          font-weight: 600;
          border-radius: 8px;
          padding: 8px 10px;
          cursor: pointer;
        }
        .activity-log {
          margin: 0;
          padding-left: 18px;
          max-height: 180px;
          overflow: auto;
        }
        .activity-log li {
          margin: 5px 0;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 12px;
        }
        @media (max-width: 900px) {
          .app {
            grid-template-columns: 1fr;
          }
        }
        """
    }

    // MARK: - Web JS

    static func generatedWebJS(manifest: StudioViewModel.BuildManifest) -> String {
        let appSpec = generatedAppSpec(
            manifest: manifest,
            target: .web,
            deterministicHash: manifest.deterministicHash,
            generatedAt: manifest.generatedAt
        )
        return generatedWebJS(appSpec: appSpec)
    }

    static func generatedWebJS(appSpec: GeneratedAppSpec) -> String {
        let stateLiteral = jsStringArrayLiteral(appSpec.states)
        let controlLiteral = jsStringArrayLiteral(appSpec.controls)
        let capabilityLiteral = jsStringArrayLiteral(appSpec.capabilities)
        let screenLiteral = jsGeneratedScreenArrayLiteral(appSpec.screens)
        let transitionLiteral = jsTransitionObjectLiteral(appSpec.transitions)
        return """
        const blueprint = {
          states: \(stateLiteral),
          controls: \(controlLiteral),
          capabilities: \(capabilityLiteral),
          screens: \(screenLiteral),
          transitions: \(transitionLiteral)
        };

        const stateSelect = document.getElementById("state-select");
        const stateBadge = document.getElementById("state-badge");
        const screenList = document.getElementById("screen-list");
        const screenSummary = document.getElementById("screen-summary");
        const controls = document.getElementById("controls");
        const capabilityGrid = document.getElementById("capability-grid");
        const activityLog = document.getElementById("activity-log");

        let selectedState = blueprint.states[0] || "Default";
        let selectedScreenID = blueprint.screens[0]?.id || "";

        function activeScreen() {
          return blueprint.screens.find((screen) => screen.id === selectedScreenID) || blueprint.screens[0] || null;
        }

        function chooseScreenForState(state) {
          return blueprint.screens.find((screen) => screen.state === state) || blueprint.screens[0] || null;
        }

        function renderState() {
          stateSelect.innerHTML = "";
          blueprint.states.forEach((state) => {
            const option = document.createElement("option");
            option.value = state;
            option.textContent = state;
            option.selected = state === selectedState;
            stateSelect.appendChild(option);
          });
          stateBadge.textContent = selectedState;
        }

        function renderCapabilities() {
          const screen = activeScreen();
          const sourceCapabilities = (screen && screen.capabilityHints && screen.capabilityHints.length)
            ? screen.capabilityHints
            : blueprint.capabilities;
          capabilityGrid.innerHTML = "";
          sourceCapabilities.forEach((capability) => {
            const card = document.createElement("div");
            card.className = "capability-card";
            card.textContent = capability;
            capabilityGrid.appendChild(card);
          });
        }

        function renderScreens() {
          screenList.innerHTML = "";
          blueprint.screens.forEach((screen) => {
            const item = document.createElement("li");
            const button = document.createElement("button");
            button.type = "button";
            button.className = `screen-item ${screen.id === selectedScreenID ? "active" : ""}`;
            button.textContent = `${screen.name} (${screen.state})`;
            button.addEventListener("click", () => {
              selectedState = screen.state;
              selectedScreenID = screen.id;
              renderState();
              renderScreens();
              renderScreenSummary();
              renderCapabilities();
              pushActivity(`screen selected -> ${screen.name}`);
            });
            item.appendChild(button);
            screenList.appendChild(item);
          });
        }

        function renderScreenSummary() {
          const screen = activeScreen();
          if (!screen) {
            screenSummary.textContent = "No screens generated.";
            return;
          }
          screenSummary.textContent = `${screen.name}: ${screen.summary}`;
        }

        function pushActivity(message) {
          const line = document.createElement("li");
          const timestamp = new Date().toLocaleTimeString();
          line.textContent = `${timestamp} \u{2022} ${message}`;
          activityLog.prepend(line);
          while (activityLog.children.length > 28) {
            activityLog.removeChild(activityLog.lastChild);
          }
        }

        function rotateState() {
          if (!blueprint.states.length) {
            return;
          }
          const index = blueprint.states.indexOf(selectedState);
          const nextIndex = index >= 0 ? (index + 1) % blueprint.states.length : 0;
          selectedState = blueprint.states[nextIndex];
          renderState();
        }

        function trigger(control) {
          if (blueprint.transitions[control]) {
            selectedState = blueprint.transitions[control];
          } else {
            rotateState();
          }
          const candidate = chooseScreenForState(selectedState);
          if (candidate) {
            selectedScreenID = candidate.id;
          }
          renderState();
          renderScreens();
          renderScreenSummary();
          renderCapabilities();
          pushActivity(`${control} -> ${selectedState}`);
        }

        function renderControls() {
          controls.innerHTML = "";
          blueprint.controls.forEach((control) => {
            const button = document.createElement("button");
            button.className = "control-btn";
            button.type = "button";
            button.textContent = control;
            button.addEventListener("click", () => trigger(control));
            controls.appendChild(button);
          });
        }

        stateSelect.addEventListener("change", (event) => {
          selectedState = event.target.value;
          const candidate = chooseScreenForState(selectedState);
          if (candidate) {
            selectedScreenID = candidate.id;
          }
          renderState();
          renderScreens();
          renderScreenSummary();
          renderCapabilities();
          pushActivity(`state changed -> ${selectedState}`);
        });

        renderState();
        renderScreens();
        renderScreenSummary();
        renderCapabilities();
        renderControls();
        pushActivity("app initialized");

        console.log("Generated full app blueprint:", blueprint);
        """
    }

    // MARK: - Internal Helpers

    private static func normalizedStateNames(from manifest: StudioViewModel.BuildManifest) -> [String] {
        let states = manifest.inferredStates
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return states.isEmpty ? ["Default"] : Array(Set(states)).sorted()
    }

    private static func normalizedControlLabels(from manifest: StudioViewModel.BuildManifest) -> [String] {
        let controls = manifest.inferredControls
            .map(\.label)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return controls.isEmpty ? ["Primary Action"] : Array(Set(controls)).sorted()
    }

    private static func normalizedCapabilities(from manifest: StudioViewModel.BuildManifest) -> [String] {
        let capabilities = manifest.capabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return capabilities.isEmpty ? ["Core workflow support"] : capabilities
    }

    private static func inferredTransitions(states: [String], controls: [String]) -> [GeneratedFlowTransition] {
        guard !states.isEmpty, !controls.isEmpty else { return [] }
        return controls.enumerated().map { index, control in
            let fromState = states[index % states.count]
            let toState = states[(index + 1) % states.count]
            return GeneratedFlowTransition(
                id: deterministicUUID(seed: "transition|\(control)|\(fromState)|\(toState)"),
                controlLabel: control,
                fromState: fromState,
                toState: toState,
                rationale: "Sequential flow inferred from control order."
            )
        }
    }

    private static func inferredScreens(
        manifest: StudioViewModel.BuildManifest,
        states: [String],
        capabilities: [String]
    ) -> [GeneratedAppScreen] {
        let defaultCapabilities = capabilities.isEmpty ? ["Core workflow support"] : capabilities
        let stateLookup = Dictionary(uniqueKeysWithValues: manifest.inferredStates.map { ($0.id, $0.name) })
        var screens: [GeneratedAppScreen] = []
        var seenNames: Set<String> = []

        for (index, suggested) in manifest.suggestedStateArtboards.prefix(16).enumerated() {
            let suggestedName = suggested.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedState = suggested.sourceStateID.flatMap { stateLookup[$0] } ?? states[index % max(1, states.count)]
            let fallbackName = mappedState.isEmpty ? "Screen \(index + 1)" : "\(mappedState) Screen"
            let name = suggestedName.isEmpty ? fallbackName : suggestedName
            guard !name.isEmpty, !seenNames.contains(name) else { continue }
            seenNames.insert(name)

            let reason = suggested.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = reason.isEmpty
                ? "Generated from \(manifest.activeArtboardName) for state \(mappedState)."
                : reason

            screens.append(
                GeneratedAppScreen(
                    id: deterministicUUID(seed: "screen|\(manifest.projectID)|\(name)|\(mappedState)|\(index)"),
                    name: name,
                    state: mappedState.isEmpty ? (states.first ?? "Default") : mappedState,
                    summary: summary,
                    capabilityHints: Array(defaultCapabilities.prefix(3))
                )
            )
        }

        if screens.isEmpty {
            for (index, state) in states.enumerated() {
                let name = "\(state) Screen"
                screens.append(
                    GeneratedAppScreen(
                        id: deterministicUUID(seed: "screen|\(manifest.projectID)|\(state)|\(index)"),
                        name: name,
                        state: state,
                        summary: "Generated from \(manifest.activeArtboardName) for state \(state).",
                        capabilityHints: Array(defaultCapabilities.prefix(3))
                    )
                )
            }
        }

        return screens
    }

    // MARK: - String Formatting Helpers

    private static func markdownList(_ values: [String], fallback: String) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "- \(fallback)" }
        return cleaned.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func escapedSwiftString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func swiftStringArrayLiteral(_ values: [String]) -> String {
        let escaped = values.map { "\"\(escapedSwiftString($0))\"" }
        return "[\(escaped.joined(separator: ", "))]"
    }

    private static func swiftStringDictionaryLiteral(_ entries: [(String, String)]) -> String {
        let pairs = entries.map { key, value in
            "\"\(escapedSwiftString(key))\": \"\(escapedSwiftString(value))\""
        }
        return "[\(pairs.joined(separator: ", "))]"
    }

    private static func swiftGeneratedScreenArrayLiteral(_ screens: [GeneratedAppScreen]) -> String {
        let rows = screens.map { screen in
            let id = escapedSwiftString(screen.id.uuidString)
            let name = escapedSwiftString(screen.name)
            let state = escapedSwiftString(screen.state)
            let summary = escapedSwiftString(screen.summary)
            let capabilityHints = swiftStringArrayLiteral(screen.capabilityHints)
            return "GeneratedScreen(id: \"\(id)\", name: \"\(name)\", state: \"\(state)\", summary: \"\(summary)\", capabilityHints: \(capabilityHints))"
        }
        if rows.isEmpty {
            return "[GeneratedScreen.fallback]"
        }
        return "[\(rows.joined(separator: ", "))]"
    }

    private static func escapedJSString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    private static func jsStringArrayLiteral(_ values: [String]) -> String {
        let escaped = values.map { "\"\(escapedJSString($0))\"" }
        return "[\(escaped.joined(separator: ", "))]"
    }

    private static func jsTransitionObjectLiteral(_ transitions: [GeneratedFlowTransition]) -> String {
        let pairs = transitions.map { transition in
            "\"\(escapedJSString(transition.controlLabel))\": \"\(escapedJSString(transition.toState))\""
        }
        return "{\(pairs.joined(separator: ", "))}"
    }

    private static func jsGeneratedScreenArrayLiteral(_ screens: [GeneratedAppScreen]) -> String {
        let rows = screens.map { screen in
            let id = escapedJSString(screen.id.uuidString)
            let name = escapedJSString(screen.name)
            let state = escapedJSString(screen.state)
            let summary = escapedJSString(screen.summary)
            let capabilityHints = jsStringArrayLiteral(screen.capabilityHints)
            return "{ id: \"\(id)\", name: \"\(name)\", state: \"\(state)\", summary: \"\(summary)\", capabilityHints: \(capabilityHints) }"
        }
        if rows.isEmpty {
            return "[]"
        }
        return "[\(rows.joined(separator: ", "))]"
    }

    private static func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func writeString(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

import Foundation

// MARK: - macOS Full App Templates

extension ScaffoldGenerator {

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
                } else if let fallback = inferredStates.first {
                    selectedState = fallback
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
}

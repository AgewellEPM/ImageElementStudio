import Foundation

// MARK: - iOS Full App Templates

extension ScaffoldGenerator {

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
                } else if let fallback = inferredStates.first {
                    selectedState = fallback
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
}

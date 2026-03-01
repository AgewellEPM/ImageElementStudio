import SwiftUI

@main
struct ImageElementStudioApp: App {
    @StateObject private var viewModel = StudioViewModel()
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var showOnboarding = false

    init() {
        // Migrate any API keys that were previously stored in UserDefaults
        // into the Keychain. This runs once and removes the UserDefaults entries.
        KeychainService.migrateKeysFromUserDefaultsIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Image Element Studio") {
            StudioRootView(viewModel: viewModel)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: Binding(
                        get: { showOnboarding },
                        set: { newValue in
                            showOnboarding = newValue
                            if !newValue {
                                onboardingCompleted = true
                            }
                        }
                    ))
                    .interactiveDismissDisabled()
                }
                .onAppear {
                    if !onboardingCompleted {
                        showOnboarding = true
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            StudioMenuCommands(viewModel: viewModel)
        }

        Settings {
            SettingsView()
        }

        Window("About Image Element Studio", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

private struct StudioMenuCommands: Commands {
    @ObservedObject var viewModel: StudioViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                viewModel.createNewProject(named: nil)
            }
            .keyboardShortcut("n")

            Button("Upload Design...") {
                viewModel.chooseImage()
            }
            .keyboardShortcut("o")

            Button("Analyze Design") {
                viewModel.analyzeCurrentImage()
            }
            .keyboardShortcut("r")
            .disabled(viewModel.selectedImage == nil || viewModel.isAnalyzing)

            Button("Start Strategy From Idea...") {
                viewModel.promptStrategyFromIdea()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Project...") {
                viewModel.saveProjectPackage()
            }
            .keyboardShortcut("s")

            Button("Export JSON...") {
                viewModel.exportJSON()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(after: .saveItem) {
            Button("Clear Project Memory") {
                viewModel.clearProjectMemory()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandMenu("Strategy") {
            Button("Start Strategy From Idea") {
                viewModel.promptStrategyFromIdea()
            }

            Button("Continue Strategy") {
                viewModel.continueStrategy()
            }
            .disabled(viewModel.strategySession == nil)

            Button("Finalize Spec") {
                viewModel.finalizeStrategySpec()
            }
            .disabled(viewModel.strategySession == nil && viewModel.acceptedStrategySpec == nil)

            Button("Generate Mockups") {
                viewModel.finalizeAndGenerateMockups()
            }

            Button("Generate Full Stack") {
                viewModel.generateFullStackBuild()
            }
        }

        CommandMenu("Build") {
            Button("Generate App from Design") {
                viewModel.generateAndBuildFromCurrentImage()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!viewModel.canGenerateApp)

            Divider()

            ForEach(StudioViewModel.BuildTarget.allCases) { target in
                Button("Build \(target.title) Setup") {
                    viewModel.setupProjectBuild(for: target)
                }
                .disabled(!viewModel.canExportBuildArtifacts || viewModel.isSettingUpBuild)
            }

            Divider()

            Button("Toggle Build Output") {
                viewModel.showBuildOutput.toggle()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        CommandMenu("Edit Layout") {
            Button("Nudge Left") {
                viewModel.keyboardNudgeLeft()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Nudge Right") {
                viewModel.keyboardNudgeRight()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Nudge Up") {
                viewModel.keyboardNudgeUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("Nudge Down") {
                viewModel.keyboardNudgeDown()
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            Divider()

            Button("Fast Nudge Left") {
                viewModel.keyboardNudgeLeft(fast: true)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.shift])

            Button("Fast Nudge Right") {
                viewModel.keyboardNudgeRight(fast: true)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.shift])

            Button("Fast Nudge Up") {
                viewModel.keyboardNudgeUp(fast: true)
            }
            .keyboardShortcut(.upArrow, modifiers: [.shift])

            Button("Fast Nudge Down") {
                viewModel.keyboardNudgeDown(fast: true)
            }
            .keyboardShortcut(.downArrow, modifiers: [.shift])

            Divider()

            Button("Rotate Clockwise") {
                viewModel.keyboardRotateClockwise()
            }
            .keyboardShortcut("]", modifiers: [.command])

            Button("Rotate Counterclockwise") {
                viewModel.keyboardRotateCounterclockwise()
            }
            .keyboardShortcut("[", modifiers: [.command])

            Divider()

            Button("Distribute Horizontally") {
                viewModel.distributeSelectedElementsHorizontally()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button("Distribute Vertically") {
                viewModel.distributeSelectedElementsVertically()
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Divider()

            Button("Run Pro Editing Benchmark") {
                viewModel.runProEditingBenchmark()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
        }

        CommandMenu("Components") {
            Button("Create Component From Selection") {
                viewModel.createComponentFromSelection(named: nil)
            }
            .keyboardShortcut("g", modifiers: [.command, .option])

            Button("Create Component Instance") {
                viewModel.createComponentInstanceFromSelectedComponent()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button("Export Interop Package") {
                viewModel.exportInteropPackage()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(!viewModel.canExportBuildArtifacts)
        }

        CommandMenu("Review") {
            Button("Set Approved") {
                viewModel.setReviewApprovalState(.approved)
            }
            Button("Set Pending") {
                viewModel.setReviewApprovalState(.pending)
            }
            Button("Request Changes") {
                viewModel.setReviewApprovalState(.changesRequested)
            }
        }
    }
}

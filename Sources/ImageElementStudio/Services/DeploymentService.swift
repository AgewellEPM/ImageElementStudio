import AppKit
import Foundation
import os

// MARK: - DeploymentService

/// Manages the multi-step deployment wizard and orchestrates archive, export,
/// DMG creation, and notarization through `XcodeToolchainService`.
/// The ViewModel forwards deployment actions to this service and subscribes to
/// `objectWillChange` so SwiftUI views update automatically.
@MainActor
final class DeploymentService: ObservableObject {

    // MARK: - Dependencies

    let toolchainService: XcodeToolchainService
    let signingService: SigningService

    private let logger = Logger(subsystem: AppLogger.subsystem, category: "deployment")

    // MARK: - Wizard State

    @Published var currentStep: DeploymentStep = .chooseTarget
    @Published var selectedTarget: DeploymentTarget = .directNotarized
    @Published var signingConfig: SigningConfiguration = SigningConfiguration()
    @Published var appMetadata: AppDeploymentMetadata = AppDeploymentMetadata()

    // MARK: - Pipeline State

    @Published var isDeploying: Bool = false
    @Published var deploymentProgress: Double = 0
    @Published var deploymentStatusLine: String = ""
    @Published var deploymentError: String?
    @Published var deploymentResult: DeploymentResult?
    @Published var buildOutput: [String] = []

    // MARK: - App Store Connect credentials (for App Store / TestFlight)

    @Published var appleID: String = ""
    @Published var appSpecificPassword: String = ""

    // MARK: - Init

    init(toolchainService: XcodeToolchainService, signingService: SigningService) {
        self.toolchainService = toolchainService
        self.signingService = signingService

        // Try to load saved signing config
        if let saved = signingService.loadSigningConfig() {
            self.signingConfig = saved
        }
    }

    // MARK: - Step Navigation

    var canAdvance: Bool {
        switch currentStep {
        case .chooseTarget:
            return true
        case .configureSigning:
            return signingConfig.isValid
        case .appMetadata:
            return appMetadata.isValid
        case .buildArchive:
            return deploymentResult?.succeeded == true
        case .submitExport:
            return false // terminal step
        }
    }

    var canGoBack: Bool {
        currentStep != .chooseTarget && !isDeploying
    }

    var isTerminalStep: Bool {
        currentStep == .submitExport
    }

    func advanceStep() {
        guard canAdvance else { return }
        let allSteps = DeploymentStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex + 1 < allSteps.count else { return }
        currentStep = allSteps[currentIndex + 1]
    }

    func goBack() {
        guard canGoBack else { return }
        let allSteps = DeploymentStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex > 0 else { return }
        currentStep = allSteps[currentIndex - 1]
    }

    func reset() {
        currentStep = .chooseTarget
        isDeploying = false
        deploymentProgress = 0
        deploymentStatusLine = ""
        deploymentError = nil
        deploymentResult = nil
        buildOutput = []
    }

    // MARK: - Populate from existing project

    func populateFromProject(name: String, bundleIDBase: String, target: String) {
        appMetadata.displayName = name
        appMetadata.bundleID = bundleIDBase.isEmpty
            ? "com.imageelementstudio.generated.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
            : bundleIDBase
    }

    // MARK: - Deployment Execution

    func runDeployment(projectDirectory: URL, scheme: String) async {
        guard !isDeploying else { return }
        isDeploying = true
        deploymentError = nil
        deploymentResult = nil
        buildOutput = []
        deploymentProgress = 0

        logger.info("Starting deployment: target=\(self.selectedTarget.rawValue), project=\(projectDirectory.path)")

        // Step 1: Write ExportOptions.plist
        deploymentStatusLine = "Preparing export options..."
        deploymentProgress = 0.1

        let exportPlistContent = toolchainService.generateExportOptionsPlist(
            target: selectedTarget,
            teamID: signingConfig.teamID,
            signingIdentity: signingConfig.signingIdentity,
            bundleID: appMetadata.bundleID
        )

        let exportPlistPath = projectDirectory.appendingPathComponent("ExportOptions.plist")
        do {
            try exportPlistContent.write(to: exportPlistPath, atomically: true, encoding: .utf8)
        } catch {
            deploymentError = "Failed to write ExportOptions.plist: \(error.localizedDescription)"
            isDeploying = false
            return
        }

        // Step 2: Archive
        deploymentStatusLine = "Archiving project..."
        deploymentProgress = 0.2

        let archivePath = projectDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(appMetadata.displayName).xcarchive")
            .path

        let xcodeProjectPath: String
        // Find .xcodeproj in the directory
        if let proj = try? FileManager.default.contentsOfDirectory(atPath: projectDirectory.path)
            .first(where: { $0.hasSuffix(".xcodeproj") }) {
            xcodeProjectPath = projectDirectory.appendingPathComponent(proj).path
        } else {
            xcodeProjectPath = projectDirectory.appendingPathComponent("\(scheme).xcodeproj").path
        }

        let archiveResult = await toolchainService.archiveProject(
            projectPath: xcodeProjectPath,
            scheme: scheme,
            archivePath: archivePath,
            signingConfig: signingConfig,
            metadata: appMetadata,
            onOutput: { [weak self] line in
                Task { @MainActor in
                    self?.buildOutput.append(line)
                }
            }
        )

        guard archiveResult.succeeded else {
            deploymentError = "Archive failed (exit code \(archiveResult.exitCode)): \(archiveResult.errorOutput)"
            isDeploying = false
            return
        }

        deploymentProgress = 0.5

        // Step 3: Export or Submit
        let exportDir = projectDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(appMetadata.displayName)-export")

        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        if selectedTarget == .directNotarized {
            // Export as .app, then create DMG and notarize
            deploymentStatusLine = "Exporting archive..."
            deploymentProgress = 0.6

            let exportResult = await toolchainService.exportArchive(
                archivePath: archivePath,
                exportPath: exportDir.path,
                exportOptionsPlistPath: exportPlistPath.path,
                onOutput: { [weak self] line in
                    Task { @MainActor in
                        self?.buildOutput.append(line)
                    }
                }
            )

            guard exportResult.succeeded else {
                deploymentError = "Export failed: \(exportResult.errorOutput)"
                isDeploying = false
                return
            }

            // Create DMG
            deploymentStatusLine = "Creating DMG..."
            deploymentProgress = 0.7

            let appPath = exportResult.outputFiles.first(where: { $0.hasSuffix(".app") })
                ?? exportDir.appendingPathComponent("\(appMetadata.displayName).app").path
            let dmgPath = exportDir.appendingPathComponent("\(appMetadata.displayName)-\(appMetadata.version).dmg").path

            let dmgSuccess = await toolchainService.createDMG(
                appPath: appPath,
                outputPath: dmgPath,
                volumeName: appMetadata.displayName
            )

            if dmgSuccess && !appleID.isEmpty && !appSpecificPassword.isEmpty {
                // Notarize
                deploymentStatusLine = "Notarizing..."
                deploymentProgress = 0.8

                let notarizeResult = await toolchainService.notarizeApp(
                    filePath: dmgPath,
                    appleID: appleID,
                    teamID: signingConfig.teamID,
                    appPassword: appSpecificPassword,
                    onOutput: { [weak self] line in
                        Task { @MainActor in
                            self?.buildOutput.append(line)
                        }
                    }
                )

                deploymentResult = DeploymentResult(
                    target: selectedTarget.rawValue,
                    outputPath: dmgPath,
                    archivePath: archivePath,
                    succeeded: notarizeResult.succeeded,
                    errorMessage: notarizeResult.succeeded ? nil : notarizeResult.output,
                    submissionID: notarizeResult.submissionID
                )
            } else {
                deploymentResult = DeploymentResult(
                    target: selectedTarget.rawValue,
                    outputPath: dmgSuccess ? dmgPath : appPath,
                    archivePath: archivePath,
                    succeeded: true,
                    errorMessage: nil
                )
            }
        } else {
            // App Store / TestFlight / Ad Hoc — export archive
            deploymentStatusLine = "Exporting for \(selectedTarget.displayName)..."
            deploymentProgress = 0.7

            let exportResult = await toolchainService.exportArchive(
                archivePath: archivePath,
                exportPath: exportDir.path,
                exportOptionsPlistPath: exportPlistPath.path,
                onOutput: { [weak self] line in
                    Task { @MainActor in
                        self?.buildOutput.append(line)
                    }
                }
            )

            let outputFile = exportResult.outputFiles.first ?? exportDir.path

            deploymentResult = DeploymentResult(
                target: selectedTarget.rawValue,
                outputPath: outputFile,
                archivePath: archivePath,
                succeeded: exportResult.succeeded,
                errorMessage: exportResult.succeeded ? nil : exportResult.errorOutput
            )
        }

        deploymentProgress = 1.0
        deploymentStatusLine = deploymentResult?.succeeded == true ? "Deployment complete" : "Deployment failed"
        isDeploying = false

        if let result = deploymentResult {
            logger.info("Deployment finished: succeeded=\(result.succeeded), output=\(result.outputPath)")
        }
    }

    // MARK: - Open in Xcode

    func openInXcode(projectDirectory: URL) {
        toolchainService.openInXcode(projectDirectory: projectDirectory.path)
    }

    // MARK: - Reveal in Finder

    func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

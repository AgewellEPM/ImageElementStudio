import Foundation
import os

extension XcodeToolchainService {

    // MARK: - Result Types

    struct ArchiveResult: Sendable {
        let archivePath: String
        let exitCode: Int32
        let duration: TimeInterval
        let succeeded: Bool
        let errorOutput: String
    }

    struct ExportResult: Sendable {
        let exportPath: String
        let exitCode: Int32
        let succeeded: Bool
        let outputFiles: [String]
        let errorOutput: String
    }

    struct NotarizationResult: Sendable {
        let succeeded: Bool
        let submissionID: String?
        let output: String
    }

    // MARK: - Archive

    /// Archive an Xcode project using `xcodebuild archive`.
    /// Injects signing config: DEVELOPMENT_TEAM, CODE_SIGN_IDENTITY, CODE_SIGN_STYLE.
    func archiveProject(
        projectPath: String,
        scheme: String,
        archivePath: String,
        signingConfig: SigningConfiguration,
        metadata: AppDeploymentMetadata,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> ArchiveResult {
        let start = Date()

        let command = [
            "xcodebuild archive",
            "-project \(shellEscape(projectPath))",
            "-scheme \(shellEscape(scheme))",
            "-archivePath \(shellEscape(archivePath))",
            "DEVELOPMENT_TEAM=\(shellEscape(signingConfig.teamID))",
            "CODE_SIGN_IDENTITY=\(shellEscape(signingConfig.signingIdentity))",
            "CODE_SIGN_STYLE=\(shellEscape(signingConfig.codeSignStyle))",
            "PRODUCT_BUNDLE_IDENTIFIER=\(shellEscape(metadata.bundleID))",
            "MARKETING_VERSION=\(shellEscape(metadata.version))",
            "CURRENT_PROJECT_VERSION=\(shellEscape(metadata.buildNumber))",
            "IPHONEOS_DEPLOYMENT_TARGET=\(shellEscape(metadata.minimumDeploymentTarget))",
            "2>&1"
        ].joined(separator: " ")

        AppLogger.info("Archiving project: \(scheme) -> \(archivePath)", category: .export)

        let (exitCode, errorOutput) = await runStreamingShell(command, onOutput: onOutput)
        let duration = Date().timeIntervalSince(start)

        let result = ArchiveResult(
            archivePath: archivePath,
            exitCode: exitCode,
            duration: duration,
            succeeded: exitCode == 0,
            errorOutput: errorOutput
        )

        if result.succeeded {
            AppLogger.info("Archive succeeded in \(String(format: "%.1f", duration))s", category: .export)
        } else {
            AppLogger.error("Archive failed (exit \(exitCode))", category: .export)
        }

        return result
    }

    // MARK: - Export Archive

    /// Export an archive using `xcodebuild -exportArchive`.
    func exportArchive(
        archivePath: String,
        exportPath: String,
        exportOptionsPlistPath: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> ExportResult {
        let command = [
            "xcodebuild -exportArchive",
            "-archivePath \(shellEscape(archivePath))",
            "-exportPath \(shellEscape(exportPath))",
            "-exportOptionsPlist \(shellEscape(exportOptionsPlistPath))",
            "2>&1"
        ].joined(separator: " ")

        AppLogger.info("Exporting archive: \(archivePath) -> \(exportPath)", category: .export)

        let (exitCode, fullOutput) = await runStreamingShell(command, onOutput: onOutput)

        // Gather output files from the export directory
        var outputFiles: [String] = []
        if exitCode == 0 {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: exportPath) {
                outputFiles = contents.map { (exportPath as NSString).appendingPathComponent($0) }
            }
        }

        let result = ExportResult(
            exportPath: exportPath,
            exitCode: exitCode,
            succeeded: exitCode == 0,
            outputFiles: outputFiles,
            errorOutput: exitCode == 0 ? "" : fullOutput
        )

        if result.succeeded {
            AppLogger.info("Export succeeded with \(outputFiles.count) file(s)", category: .export)
        } else {
            AppLogger.error("Export failed (exit \(exitCode))", category: .export)
        }

        return result
    }

    // MARK: - ExportOptions.plist Generation

    /// Generate the XML content for an ExportOptions.plist suited to the given deployment target.
    func generateExportOptionsPlist(
        target: DeploymentTarget,
        teamID: String,
        signingIdentity: String,
        bundleID: String
    ) -> String {
        var entries: [String] = []

        entries.append("    <key>method</key>")
        entries.append("    <string>\(target.exportMethod)</string>")

        entries.append("    <key>teamID</key>")
        entries.append("    <string>\(teamID)</string>")

        entries.append("    <key>signingStyle</key>")
        entries.append("    <string>automatic</string>")

        entries.append("    <key>signingCertificate</key>")
        entries.append("    <string>\(signingIdentity)</string>")

        // Provisioning profiles mapping
        entries.append("    <key>provisioningProfiles</key>")
        entries.append("    <dict/>")

        switch target {
        case .appStore, .testFlight:
            entries.append("    <key>uploadBitcode</key>")
            entries.append("    <false/>")
            entries.append("    <key>uploadSymbols</key>")
            entries.append("    <true/>")
        case .adHoc:
            entries.append("    <key>compileBitcode</key>")
            entries.append("    <false/>")
            entries.append("    <key>thinning</key>")
            entries.append("    <string>&lt;none&gt;</string>")
        case .directNotarized:
            // Developer ID exports don't need bitcode or thinning
            break
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(entries.joined(separator: "\n"))
        </dict>
        </plist>
        """

        return plist
    }

    // MARK: - Notarization

    /// Notarize an app or DMG using `xcrun notarytool`, then staple on success.
    func notarizeApp(
        filePath: String,
        appleID: String,
        teamID: String,
        appPassword: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> NotarizationResult {
        AppLogger.info("Submitting for notarization: \(filePath)", category: .export)

        let submitCommand = [
            "xcrun notarytool submit",
            shellEscape(filePath),
            "--wait",
            "--apple-id \(shellEscape(appleID))",
            "--team-id \(shellEscape(teamID))",
            "--password \(shellEscape(appPassword))",
            "2>&1"
        ].joined(separator: " ")

        let (submitExit, submitOutput) = await runStreamingShell(submitCommand, onOutput: onOutput)

        // Parse submission ID from output (format: "  id: <uuid>")
        var submissionID: String?
        for line in submitOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("id:") {
                submissionID = trimmed
                    .replacingOccurrences(of: "id:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard submitExit == 0 else {
            AppLogger.error("Notarization submission failed (exit \(submitExit))", category: .export)
            return NotarizationResult(
                succeeded: false,
                submissionID: submissionID,
                output: submitOutput
            )
        }

        // Check if the output indicates acceptance
        let accepted = submitOutput.contains("status: Accepted")
        guard accepted else {
            AppLogger.error("Notarization was not accepted", category: .export)
            return NotarizationResult(
                succeeded: false,
                submissionID: submissionID,
                output: submitOutput
            )
        }

        // Staple the notarization ticket onto the binary
        AppLogger.info("Stapling notarization ticket to \(filePath)", category: .export)

        let stapleCommand = "xcrun stapler staple \(shellEscape(filePath)) 2>&1"
        let (stapleExit, stapleOutput) = await runStreamingShell(stapleCommand, onOutput: onOutput)

        let fullOutput = submitOutput + "\n" + stapleOutput
        let succeeded = stapleExit == 0

        if succeeded {
            AppLogger.info("Notarization and stapling succeeded", category: .export)
        } else {
            AppLogger.error("Stapling failed (exit \(stapleExit))", category: .export)
        }

        return NotarizationResult(
            succeeded: succeeded,
            submissionID: submissionID,
            output: fullOutput
        )
    }

    // MARK: - DMG Creation

    /// Create a DMG disk image from an .app bundle using `hdiutil`.
    func createDMG(
        appPath: String,
        outputPath: String,
        volumeName: String
    ) async -> Bool {
        AppLogger.info("Creating DMG: \(volumeName) -> \(outputPath)", category: .export)

        let command = [
            "hdiutil create",
            "-volname \(shellEscape(volumeName))",
            "-srcfolder \(shellEscape(appPath))",
            "-ov",
            "-format UDZO",
            shellEscape(outputPath),
            "2>&1"
        ].joined(separator: " ")

        let (exitCode, output) = await runShellCommand(command)

        if exitCode == 0 {
            AppLogger.info("DMG created successfully at \(outputPath)", category: .export)
        } else {
            AppLogger.error("DMG creation failed (exit \(exitCode)): \(output)", category: .export)
        }

        return exitCode == 0
    }

    // MARK: - Open in Xcode

    /// Open a project directory in Xcode, looking for .xcworkspace first, then .xcodeproj.
    func openInXcode(projectDirectory: String) {
        #if !APP_STORE
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: projectDirectory)) ?? []

        // Prefer workspace over project
        let workspace = contents.first { $0.hasSuffix(".xcworkspace") }
        let project = contents.first { $0.hasSuffix(".xcodeproj") }

        let pathToOpen: String
        if let workspace {
            pathToOpen = (projectDirectory as NSString).appendingPathComponent(workspace)
        } else if let project {
            pathToOpen = (projectDirectory as NSString).appendingPathComponent(project)
        } else {
            pathToOpen = projectDirectory
        }

        AppLogger.info("Opening in Xcode: \(pathToOpen)", category: .export)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "open \(shellEscape(pathToOpen))"]

        do {
            try process.run()
        } catch {
            AppLogger.error("Failed to open in Xcode: \(error.localizedDescription)", category: .export)
        }
        #endif
    }

    // MARK: - Private Shell Helpers

    /// Run a shell command with line-by-line streaming output via callback.
    /// Follows the same Process/Pipe pattern as `runStreamingCommand` in the main file.
    private func runStreamingShell(
        _ command: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> (exitCode: Int32, output: String) {
        #if !APP_STORE
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let accumulator = OutputAccumulator()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let text = String(data: data, encoding: .utf8) else { return }
                accumulator.append(text)

                let lines = text.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    onOutput(line)
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: (proc.terminationStatus, accumulator.output))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, "Failed to launch process: \(error.localizedDescription)"))
            }
        }
        #else
        return (exitCode: 1, output: "[App Store build] Shell execution is not available.")
        #endif
    }

    /// Run a shell command and return the collected output (non-streaming).
    /// Follows the same pattern as `runCommand` in the main file.
    private func runShellCommand(_ command: String) async -> (exitCode: Int32, output: String) {
        #if !APP_STORE
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, output))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, "Failed: \(error.localizedDescription)"))
            }
        }
        #else
        return (exitCode: 1, output: "[App Store build] Shell execution is not available.")
        #endif
    }
}

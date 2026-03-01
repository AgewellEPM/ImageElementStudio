import Foundation

@MainActor
final class BuildPipelineCoordinator: ObservableObject {

    // MARK: - Dependencies

    let toolchainService = XcodeToolchainService()
    let simulatorService = SimulatorService()

    // MARK: - Pipeline State

    enum PipelineStep: String, CaseIterable, Identifiable, Sendable {
        case verifyToolchain = "Verify Toolchain"
        case generateProject = "Generate Xcode Project"
        case selectSimulator = "Select Simulator"
        case buildProject = "Build Project"
        case fixErrors = "Fix Build Errors"
        case installApp = "Install App"
        case launchApp = "Launch App"

        var id: String { rawValue }
    }

    struct PipelineStepStatus: Identifiable, Sendable {
        let step: PipelineStep
        var state: StepState
        var detail: String?

        var id: String { step.id }

        enum StepState: Sendable {
            case pending
            case active
            case succeeded
            case failed
            case skipped
        }
    }

    @Published var steps: [PipelineStepStatus] = []
    @Published var isRunning: Bool = false
    @Published var currentStep: PipelineStep?
    @Published var pipelineError: String?

    private var cancelled: Bool = false

    // MARK: - Build Pipeline

    /// Run the full pipeline: verify -> xcodegen -> select sim -> build -> fix errors -> install -> launch
    func runFullPipeline(
        projectDirectory: URL,
        scheme: String,
        bundleID: String,
        sdk: XcodeToolchainService.SDK = .iphonesimulator,
        onBuildError: (@Sendable (String) async -> [GeneratedFileEntry]?)? = nil
    ) async -> Bool {
        guard !isRunning else { return false }

        cancelled = false
        isRunning = true
        pipelineError = nil

        // Initialize all steps as pending
        steps = PipelineStep.allCases.map { PipelineStepStatus(step: $0, state: .pending) }

        let isiOS = sdk == .iphonesimulator

        defer { isRunning = false }

        // --- Step 1: Verify Toolchain ---
        guard !cancelled else { return handleCancellation() }
        markStep(.verifyToolchain, state: .active)

        await toolchainService.detectToolchain()
        let status = toolchainService.toolchainStatus

        let toolchainReady = isiOS ? status.isReadyForiOS : status.isReady
        guard toolchainReady else {
            let missing = describeMissingToolchain(status, isiOS: isiOS)
            markStep(.verifyToolchain, state: .failed, detail: missing)
            return failPipeline(after: .verifyToolchain, error: missing)
        }

        let toolchainDetail: String
        if let version = status.xcodeVersion {
            toolchainDetail = version
        } else {
            toolchainDetail = "Ready"
        }
        markStep(.verifyToolchain, state: .succeeded, detail: toolchainDetail)

        // --- Step 2: Generate Xcode Project (iOS only) ---
        guard !cancelled else { return handleCancellation() }
        if isiOS {
            markStep(.generateProject, state: .active)

            let genResult = await toolchainService.generateXcodeProject(at: projectDirectory)
            guard genResult.exitCode == 0 else {
                let detail = "xcodegen failed (exit \(genResult.exitCode)): \(genResult.output)"
                markStep(.generateProject, state: .failed, detail: detail)
                return failPipeline(after: .generateProject, error: detail)
            }

            markStep(.generateProject, state: .succeeded, detail: "Project generated")
        } else {
            markStep(.generateProject, state: .skipped, detail: "Not needed for macOS")
        }

        // --- Step 3: Select Simulator (iOS only) ---
        guard !cancelled else { return handleCancellation() }
        var simulatorID: String? = nil

        if isiOS {
            markStep(.selectSimulator, state: .active)

            await simulatorService.listSimulators()
            guard let sim = simulatorService.bestAvailableSimulator() else {
                let detail = "No available iOS simulators found"
                markStep(.selectSimulator, state: .failed, detail: detail)
                return failPipeline(after: .selectSimulator, error: detail)
            }

            let booted = await simulatorService.bootSimulator(udid: sim.id)
            guard booted else {
                let detail = "Failed to boot simulator: \(sim.name)"
                markStep(.selectSimulator, state: .failed, detail: detail)
                return failPipeline(after: .selectSimulator, error: detail)
            }

            simulatorID = sim.id
            markStep(.selectSimulator, state: .succeeded, detail: "\(sim.name) (\(sim.runtime))")
        } else {
            markStep(.selectSimulator, state: .skipped, detail: "Not needed for macOS")
        }

        // --- Step 4: Build Project ---
        guard !cancelled else { return handleCancellation() }
        markStep(.buildProject, state: .active)

        var buildResult = await toolchainService.buildProject(
            at: projectDirectory,
            scheme: scheme,
            sdk: sdk,
            simulatorID: simulatorID
        )

        if buildResult.succeeded {
            markStep(.buildProject, state: .succeeded, detail: formatDuration(buildResult.duration))
        } else {
            let errorSummary = summarizeBuildErrors(buildResult)
            markStep(.buildProject, state: .failed, detail: errorSummary)

            // --- Step 5: Fix Build Errors ---
            guard !cancelled else { return handleCancellation() }
            if let onBuildError {
                markStep(.fixErrors, state: .active)

                var fixed = false
                let maxAttempts = 3

                for attempt in 1...maxAttempts {
                    guard !cancelled else { return handleCancellation() }

                    let errorDescription = formatBuildErrorsForAI(buildResult)
                    markStep(.fixErrors, state: .active, detail: "Attempt \(attempt)/\(maxAttempts)")

                    let fixedFiles = await onBuildError(errorDescription)

                    guard let fixedFiles, !fixedFiles.isEmpty else {
                        markStep(.fixErrors, state: .failed, detail: "AI could not generate fixes")
                        return failPipeline(after: .fixErrors, error: "AI fix callback returned nil or empty on attempt \(attempt)")
                    }

                    // Write fixed files to disk
                    writeFixedFiles(fixedFiles, to: projectDirectory)

                    // Retry the build
                    markStep(.buildProject, state: .active, detail: "Retry \(attempt)")
                    buildResult = await toolchainService.buildProject(
                        at: projectDirectory,
                        scheme: scheme,
                        sdk: sdk,
                        simulatorID: simulatorID
                    )

                    if buildResult.succeeded {
                        markStep(.buildProject, state: .succeeded, detail: "Fixed on attempt \(attempt)")
                        markStep(.fixErrors, state: .succeeded, detail: "Resolved in \(attempt) attempt(s)")
                        fixed = true
                        break
                    }
                }

                if !fixed {
                    let errorSummary = summarizeBuildErrors(buildResult)
                    markStep(.fixErrors, state: .failed, detail: "Failed after \(maxAttempts) attempts")
                    return failPipeline(after: .fixErrors, error: "Build still failing after \(maxAttempts) fix attempts: \(errorSummary)")
                }
            } else {
                // No AI fix callback provided
                markStep(.fixErrors, state: .skipped, detail: "No error fixer provided")
                return failPipeline(after: .buildProject, error: "Build failed: \(errorSummary)")
            }
        }

        // Build succeeded (possibly after fixes) - mark fixErrors as skipped if build succeeded first time
        if let fixStep = steps.first(where: { $0.step == .fixErrors }), fixStep.state == .pending {
            markStep(.fixErrors, state: .skipped, detail: "Build succeeded")
        }

        // --- Step 6: Install App (iOS only) ---
        guard !cancelled else { return handleCancellation() }
        if isiOS {
            markStep(.installApp, state: .active)

            guard let productPath = buildResult.productPath else {
                let detail = "Could not find built .app product path"
                markStep(.installApp, state: .failed, detail: detail)
                return failPipeline(after: .installApp, error: detail)
            }

            guard let simID = simulatorID else {
                let detail = "No simulator ID available"
                markStep(.installApp, state: .failed, detail: detail)
                return failPipeline(after: .installApp, error: detail)
            }

            let installed = await simulatorService.installApp(simulatorID: simID, appPath: productPath)
            guard installed else {
                let detail = "simctl install failed"
                markStep(.installApp, state: .failed, detail: detail)
                return failPipeline(after: .installApp, error: detail)
            }

            markStep(.installApp, state: .succeeded, detail: "Installed")
        } else {
            markStep(.installApp, state: .skipped, detail: "Not needed for macOS")
        }

        // --- Step 7: Launch App (iOS only) ---
        guard !cancelled else { return handleCancellation() }
        if isiOS {
            markStep(.launchApp, state: .active)

            guard let simID = simulatorID else {
                let detail = "No simulator ID available"
                markStep(.launchApp, state: .failed, detail: detail)
                return failPipeline(after: .launchApp, error: detail)
            }

            let launched = await simulatorService.launchApp(simulatorID: simID, bundleID: bundleID)
            guard launched else {
                let detail = "simctl launch failed for \(bundleID)"
                markStep(.launchApp, state: .failed, detail: detail)
                return failPipeline(after: .launchApp, error: detail)
            }

            markStep(.launchApp, state: .succeeded, detail: "Running")
        } else {
            markStep(.launchApp, state: .skipped, detail: "Not needed for macOS")
        }

        return true
    }

    /// Just build (skip simulator steps)
    func buildOnly(
        projectDirectory: URL,
        scheme: String,
        sdk: XcodeToolchainService.SDK = .iphonesimulator
    ) async -> XcodeToolchainService.XcodeBuildResult? {
        guard !isRunning else { return nil }

        cancelled = false
        isRunning = true
        pipelineError = nil

        // Show minimal steps for build-only
        steps = [
            PipelineStepStatus(step: .verifyToolchain, state: .pending),
            PipelineStepStatus(step: .buildProject, state: .pending),
        ]

        defer { isRunning = false }

        // Verify toolchain
        guard !cancelled else {
            _ = handleCancellation()
            return nil
        }
        markStep(.verifyToolchain, state: .active)

        await toolchainService.detectToolchain()
        let status = toolchainService.toolchainStatus
        let isiOS = sdk == .iphonesimulator
        let ready = isiOS ? status.isReadyForiOS : status.isReady

        guard ready else {
            let missing = describeMissingToolchain(status, isiOS: isiOS)
            markStep(.verifyToolchain, state: .failed, detail: missing)
            pipelineError = missing
            return nil
        }

        markStep(.verifyToolchain, state: .succeeded)

        // Build
        guard !cancelled else {
            _ = handleCancellation()
            return nil
        }
        markStep(.buildProject, state: .active)

        let result = await toolchainService.buildProject(
            at: projectDirectory,
            scheme: scheme,
            sdk: sdk
        )

        if result.succeeded {
            markStep(.buildProject, state: .succeeded, detail: formatDuration(result.duration))
        } else {
            let errorSummary = summarizeBuildErrors(result)
            markStep(.buildProject, state: .failed, detail: errorSummary)
            pipelineError = "Build failed: \(errorSummary)"
        }

        return result
    }

    func cancelPipeline() {
        cancelled = true
        toolchainService.cancelBuild()

        // Mark currently active step as failed
        for i in steps.indices {
            if steps[i].state == .active {
                steps[i].state = .failed
                steps[i].detail = "Cancelled"
            } else if steps[i].state == .pending {
                steps[i].state = .skipped
                steps[i].detail = "Cancelled"
            }
        }

        pipelineError = "Pipeline cancelled"
        isRunning = false
    }

    // MARK: - Private Helpers

    private func markStep(_ step: PipelineStep, state: PipelineStepStatus.StepState, detail: String? = nil) {
        currentStep = (state == .active) ? step : currentStep
        if let index = steps.firstIndex(where: { $0.step == step }) {
            steps[index].state = state
            steps[index].detail = detail
        }

        switch state {
        case .active:
            AppLogger.info("Pipeline step started: \(step.rawValue)", category: .build)
        case .succeeded:
            AppLogger.info("Pipeline step succeeded: \(step.rawValue)\(detail.map { " (\($0))" } ?? "")", category: .build)
        case .failed:
            AppLogger.error("Pipeline step failed: \(step.rawValue)\(detail.map { " - \($0)" } ?? "")", category: .build)
        case .skipped:
            AppLogger.debug("Pipeline step skipped: \(step.rawValue)\(detail.map { " - \($0)" } ?? "")", category: .build)
        case .pending:
            break
        }
    }

    private func failPipeline(after failedStep: PipelineStep, error: String) -> Bool {
        AppLogger.error("Pipeline failed after \(failedStep.rawValue): \(error)", category: .build)
        pipelineError = error

        // Skip all remaining steps after the failed one
        var foundFailed = false
        for i in steps.indices {
            if steps[i].step == failedStep {
                foundFailed = true
                continue
            }
            if foundFailed && steps[i].state == .pending {
                steps[i].state = .skipped
                steps[i].detail = "Skipped due to earlier failure"
            }
        }

        return false
    }

    private func handleCancellation() -> Bool {
        pipelineError = "Pipeline cancelled"
        for i in steps.indices {
            if steps[i].state == .pending {
                steps[i].state = .skipped
                steps[i].detail = "Cancelled"
            }
        }
        return false
    }

    private func describeMissingToolchain(_ status: XcodeToolchainService.ToolchainStatus, isiOS: Bool) -> String {
        var missing: [String] = []
        if !status.xcodeInstalled { missing.append("Xcode not installed") }
        if !status.commandLineToolsInstalled { missing.append("Command line tools missing") }
        if isiOS {
            if !status.xcodgenInstalled { missing.append("XcodeGen not installed") }
            if !status.availableSDKs.contains(where: { $0.contains("iphonesimulator") }) {
                missing.append("iOS Simulator SDK not available")
            }
        }
        return missing.isEmpty ? "Toolchain not ready" : missing.joined(separator: "; ")
    }

    private func summarizeBuildErrors(_ result: XcodeToolchainService.XcodeBuildResult) -> String {
        let errorCount = result.errors.count
        if errorCount == 0 {
            return "Build failed (exit code \(result.exitCode))"
        }
        let first = result.errors.first?.message ?? "Unknown error"
        if errorCount == 1 {
            return first
        }
        return "\(errorCount) errors - first: \(first)"
    }

    private func formatBuildErrorsForAI(_ result: XcodeToolchainService.XcodeBuildResult) -> String {
        var lines: [String] = []
        lines.append("Build failed with \(result.errors.count) error(s):")
        lines.append("")

        for (index, error) in result.errors.enumerated() {
            var location = ""
            if !error.file.isEmpty {
                location = error.file
                if let line = error.line {
                    location += ":\(line)"
                    if let col = error.column {
                        location += ":\(col)"
                    }
                }
                location += " - "
            }
            lines.append("  \(index + 1). \(location)\(error.message)")
        }

        if !result.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings (\(result.warnings.count)):")
            for warning in result.warnings.prefix(5) {
                lines.append("  - \(warning.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func writeFixedFiles(_ files: [GeneratedFileEntry], to projectDirectory: URL) {
        let fm = FileManager.default
        for file in files {
            let filePath = projectDirectory.appendingPathComponent(file.relativePath)
            let directory = filePath.deletingLastPathComponent()

            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                AppLogger.error("Failed to create directory \(directory.path): \(error.localizedDescription)", category: .build)
                continue
            }

            do {
                try file.content.write(to: filePath, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.error("Failed to write file \(filePath.path): \(error.localizedDescription)", category: .build)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

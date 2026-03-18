import Foundation

@MainActor
final class XcodeToolchainService: ObservableObject {

    // MARK: - Types

    struct ToolchainStatus: Sendable {
        var xcodeInstalled: Bool
        var xcodePath: String?
        var xcodeVersion: String?
        var commandLineToolsInstalled: Bool
        var xcodgenInstalled: Bool
        var xcodgenPath: String?
        var availableSDKs: [String]

        static let unknown = ToolchainStatus(
            xcodeInstalled: false, xcodePath: nil, xcodeVersion: nil,
            commandLineToolsInstalled: false, xcodgenInstalled: false,
            xcodgenPath: nil, availableSDKs: []
        )

        var isReady: Bool {
            xcodeInstalled && commandLineToolsInstalled
        }

        var isReadyForiOS: Bool {
            isReady && xcodgenInstalled && availableSDKs.contains(where: { $0.contains("iphonesimulator") })
        }
    }

    struct BuildOutputLine: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let text: String
        let kind: Kind

        enum Kind: Sendable {
            case stdout
            case stderr
            case error
            case warning
            case note
            case progress
            case success
        }
    }

    struct BuildDiagnostic: Identifiable, Sendable {
        let id = UUID()
        let file: String
        let line: Int?
        let column: Int?
        let message: String
        let kind: Kind

        enum Kind: String, Sendable { case error, warning, note }
    }

    struct XcodeBuildResult: Sendable {
        let exitCode: Int32
        let errors: [BuildDiagnostic]
        let warnings: [BuildDiagnostic]
        let productPath: String?
        let duration: TimeInterval

        var succeeded: Bool { exitCode == 0 }
    }

    enum SDK: String, Sendable {
        case iphonesimulator
        case macosx
    }

    // MARK: - Published State

    @Published var toolchainStatus: ToolchainStatus = .unknown
    @Published var isBuilding: Bool = false
    @Published var buildOutput: [BuildOutputLine] = []
    @Published var lastBuildResult: XcodeBuildResult?

    // MARK: - Private

    #if !APP_STORE
    private var buildProcess: Process?
    #endif

    // MARK: - Toolchain Detection

    func detectToolchain() async {
        let xcodePath = await runQuiet("xcode-select -p")
        let xcodeVersion = await runQuiet("xcodebuild -version 2>/dev/null | head -1")
        let cliCheck = await runQuiet("xcrun --find xcodebuild 2>/dev/null")
        let xcodgenPath = await runQuiet("which xcodegen 2>/dev/null")
        let sdkOutput = await runQuiet("xcodebuild -showsdks 2>/dev/null")

        let sdks = sdkOutput.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("-sdk ") else { return nil }
                return trimmed.components(separatedBy: "-sdk ").last?.trimmingCharacters(in: .whitespaces)
            }

        toolchainStatus = ToolchainStatus(
            xcodeInstalled: !xcodePath.isEmpty && !xcodePath.contains("error"),
            xcodePath: xcodePath.isEmpty ? nil : xcodePath.trimmingCharacters(in: .whitespacesAndNewlines),
            xcodeVersion: xcodeVersion.isEmpty ? nil : xcodeVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            commandLineToolsInstalled: !cliCheck.isEmpty,
            xcodgenInstalled: !xcodgenPath.isEmpty,
            xcodgenPath: xcodgenPath.isEmpty ? nil : xcodgenPath.trimmingCharacters(in: .whitespacesAndNewlines),
            availableSDKs: sdks
        )
    }

    // MARK: - XcodeGen

    func generateXcodeProject(at directory: URL) async -> (exitCode: Int32, output: String) {
        await runCommand("cd \(shellEscape(directory.path)) && xcodegen generate 2>&1")
    }

    // MARK: - Build (Streaming)

    func buildProject(
        at projectDirectory: URL,
        scheme: String,
        sdk: SDK,
        simulatorID: String? = nil,
        configuration: String = "Debug"
    ) async -> XcodeBuildResult {
        isBuilding = true
        buildOutput = []
        let startTime = Date()

        defer { isBuilding = false }

        let command: String
        switch sdk {
        case .iphonesimulator:
            let destination: String
            if let simID = simulatorID {
                destination = "platform=iOS Simulator,id=\(simID)"
            } else {
                destination = "platform=iOS Simulator,name=iPhone 16"
            }
            let projectPath = projectDirectory.appendingPathComponent("\(scheme).xcodeproj").path
            command = "xcodebuild -project \(shellEscape(projectPath)) -scheme \(shellEscape(scheme)) -sdk iphonesimulator -destination '\(destination)' -configuration \(configuration) ONLY_ACTIVE_ARCH=YES 2>&1"

        case .macosx:
            command = "cd \(shellEscape(projectDirectory.path)) && swift build 2>&1"
        }

        let (exitCode, _) = await runStreamingCommand(command)

        let errors = buildOutput.compactMap { line -> BuildDiagnostic? in
            parseDiagnostic(from: line.text, kind: .error)
        }
        let warnings = buildOutput.compactMap { line -> BuildDiagnostic? in
            parseDiagnostic(from: line.text, kind: .warning)
        }

        let productPath = extractProductPath(from: buildOutput.map(\.text))
        let duration = Date().timeIntervalSince(startTime)

        let result = XcodeBuildResult(
            exitCode: exitCode,
            errors: errors,
            warnings: warnings,
            productPath: productPath,
            duration: duration
        )
        lastBuildResult = result
        return result
    }

    // MARK: - Cancel Build

    func cancelBuild() {
        buildProcess?.terminate()
        buildProcess = nil
        isBuilding = false
    }

    // MARK: - Private Helpers

    final class OutputAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var _output = ""

        func append(_ text: String) {
            lock.lock()
            _output += text
            lock.unlock()
        }

        var output: String {
            lock.lock()
            defer { lock.unlock() }
            return _output
        }
    }

    private func runStreamingCommand(_ command: String) async -> (exitCode: Int32, output: String) {
        #if !APP_STORE
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            self.buildProcess = process

            let accumulator = OutputAccumulator()

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let text = String(data: data, encoding: .utf8) else { return }
                accumulator.append(text)

                let lines = text.components(separatedBy: .newlines)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for line in lines where !line.isEmpty {
                        let outputLine = BuildOutputLine(
                            timestamp: Date(),
                            text: line,
                            kind: self.classifyLine(line)
                        )
                        self.buildOutput.append(outputLine)
                    }
                }
            }

            process.terminationHandler = { [weak self] proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self?.buildProcess = nil
                }
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

    private func runQuiet(_ command: String) async -> String {
        #if !APP_STORE
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: "")
            }
        }
        #else
        return ""
        #endif
    }

    private func runCommand(_ command: String) async -> (exitCode: Int32, output: String) {
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

    private func classifyLine(_ line: String) -> BuildOutputLine.Kind {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(": error:") || trimmed.hasPrefix("error:") { return .error }
        if trimmed.contains(": warning:") || trimmed.hasPrefix("warning:") { return .warning }
        if trimmed.contains(": note:") { return .note }
        if trimmed.hasPrefix("Compiling") || trimmed.hasPrefix("Linking") || trimmed.hasPrefix("Build ") { return .progress }
        if trimmed.contains("BUILD SUCCEEDED") || trimmed.contains("Build complete!") { return .success }
        return .stdout
    }

    private func parseDiagnostic(from line: String, kind: BuildDiagnostic.Kind) -> BuildDiagnostic? {
        // Patterns are built from enum raw values ("error"/"warning") so regex compilation always succeeds.
        let pattern = "^(.+?):(\\d+):(\\d+): \(kind.rawValue): (.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            let simplePattern = "^\(kind.rawValue): (.+)$"
            if let simpleRegex = try? NSRegularExpression(pattern: simplePattern),
               let simpleMatch = simpleRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let msgRange = Range(simpleMatch.range(at: 1), in: line) {
                return BuildDiagnostic(file: "", line: nil, column: nil, message: String(line[msgRange]), kind: kind)
            }
            return nil
        }

        guard let fileRange = Range(match.range(at: 1), in: line),
              let lineRange = Range(match.range(at: 2), in: line),
              let colRange = Range(match.range(at: 3), in: line),
              let msgRange = Range(match.range(at: 4), in: line) else {
            return nil
        }

        return BuildDiagnostic(
            file: String(line[fileRange]),
            line: Int(line[lineRange]),
            column: Int(line[colRange]),
            message: String(line[msgRange]),
            kind: kind
        )
    }

    private func extractProductPath(from lines: [String]) -> String? {
        for line in lines.reversed() {
            if line.contains(".app") && (line.contains("Build/Products") || line.contains(".build/")) {
                let components = line.components(separatedBy: " ")
                for component in components {
                    if component.hasSuffix(".app") || component.contains(".app/") {
                        let appPath = component.components(separatedBy: ".app").first.map { $0 + ".app" }
                        return appPath
                    }
                }
            }
        }
        return nil
    }

    func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

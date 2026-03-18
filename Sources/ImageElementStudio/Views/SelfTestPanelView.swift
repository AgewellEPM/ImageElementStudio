import SwiftUI

/// Panel for running visual self-tests via IsolatedTester.
/// Launches the app on a virtual display, captures screenshots, and optionally
/// runs AI-driven tests using Claude Code.
struct SelfTestPanelView: View {
    @ObservedObject var viewModel: StudioViewModel
    @ObservedObject var testService: SelfTestService
    @State private var testObjective: String = "Verify the app UI loads correctly with all three panes visible"
    @State private var selectedProvider: String = "claude-code"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Self-Test", systemImage: "testtube.2")
                    .font(.headline)
                Spacer()
                statusIndicator
            }

            Divider()

            // Server controls
            HStack(spacing: 8) {
                if testService.isServerRunning {
                    Button("Stop Server") {
                        testService.stopServer()
                    }
                    .controlSize(.small)

                    if testService.activeSessionID == nil {
                        Button("Launch App") {
                            launchAppSession()
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Screenshot") {
                            captureScreenshot()
                        }
                        .controlSize(.small)
                        .disabled(testService.isCapturing)

                        Button("Stop Session") {
                            stopSession()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Start Server") {
                        startServer()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)

                    Button("Quick Test") {
                        runQuickTest()
                    }
                    .controlSize(.small)
                }
            }

            // Screenshot preview
            if let screenshot = testService.latestScreenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            // AI Test section
            if testService.activeSessionID != nil {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Test")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 6) {
                        Picker("Provider", selection: $selectedProvider) {
                            Text("Claude Code").tag("claude-code")
                            Text("Anthropic API").tag("anthropic")
                            Text("OpenAI").tag("openai")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }

                    TextField("Test objective...", text: $testObjective, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(2...4)

                    Button {
                        runAITest()
                    } label: {
                        Label(
                            testService.isRunningTest ? "Running..." : "Run AI Test",
                            systemImage: "brain"
                        )
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(testService.isRunningTest || testObjective.isEmpty)
                }
            }

            // Log
            if !testService.testLog.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(testService.testLog) { entry in
                                HStack(spacing: 4) {
                                    logIcon(entry.type)
                                    Text(entry.message)
                                        .font(.caption2)
                                        .foregroundStyle(logColor(entry.type))
                                }
                                .id(entry.id)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .onChange(of: testService.testLog.count) { _, _ in
                        if let last = testService.testLog.last {
                            proxy.scrollTo(last.id)
                        }
                    }
                }
            }

            // Error display
            if let error = testService.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(testService.isServerRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(testService.isServerRunning
                 ? (testService.activeSessionID != nil ? "Session Active" : "Server Ready")
                 : "Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func startServer() {
        Task {
            do {
                try await testService.startServer()
            } catch {
                await MainActor.run { testService.lastError = error.localizedDescription }
            }
        }
    }

    private func launchAppSession() {
        Task {
            do {
                // Find the built app executable
                let appPath = findAppExecutable()
                _ = try await testService.createSession(appPath: appPath)
                // Auto-screenshot after launch
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = try await testService.captureScreenshot()
            } catch {
                await MainActor.run { testService.lastError = error.localizedDescription }
            }
        }
    }

    private func captureScreenshot() {
        Task {
            do {
                _ = try await testService.captureScreenshot()
            } catch {
                await MainActor.run { testService.lastError = error.localizedDescription }
            }
        }
    }

    private func stopSession() {
        Task {
            if let sessionId = testService.activeSessionID {
                try? await testService.stopSession(sessionId)
            }
        }
    }

    private func runQuickTest() {
        Task {
            do {
                try await testService.startServer()
                let appPath = findAppExecutable()
                _ = try await testService.createSession(appPath: appPath)
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = try await testService.captureScreenshot()
            } catch {
                await MainActor.run { testService.lastError = error.localizedDescription }
            }
        }
    }

    private func runAITest() {
        Task {
            do {
                _ = try await testService.runAITest(
                    objective: testObjective,
                    provider: selectedProvider
                )
                // Capture final screenshot after test
                _ = try? await testService.captureScreenshot()
            } catch {
                await MainActor.run { testService.lastError = error.localizedDescription }
            }
        }
    }

    private func findAppExecutable() -> String {
        #if !APP_STORE
        // Look for the built executable
        let debugPath = NSHomeDirectory() + "/ImageElementStudio/.build/debug/ImageElementStudio"
        if FileManager.default.isExecutableFile(atPath: debugPath) {
            return debugPath
        }
        let releasePath = NSHomeDirectory() + "/ImageElementStudio/.build/release/ImageElementStudio"
        if FileManager.default.isExecutableFile(atPath: releasePath) {
            return releasePath
        }
        #endif
        // Fallback: current process
        return ProcessInfo.processInfo.arguments[0]
    }

    // MARK: - Log Formatting

    @ViewBuilder
    private func logIcon(_ type: SelfTestService.TestLogEntry.LogType) -> some View {
        switch type {
        case .info:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .screenshot:
            Image(systemName: "camera.fill").foregroundStyle(.blue)
        }
    }

    private func logColor(_ type: SelfTestService.TestLogEntry.LogType) -> Color {
        switch type {
        case .info: return .secondary
        case .success: return .green
        case .error: return .red
        case .screenshot: return .blue
        }
    }
}

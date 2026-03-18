import AppKit
import Foundation

/// Wraps the IsolatedTester HTTP API to provide self-testing capabilities.
/// Launches apps on virtual displays, captures screenshots, and runs AI-driven tests
/// without interfering with the user's screen.
@MainActor
final class SelfTestService: ObservableObject {

    // MARK: - Published State

    @Published var isServerRunning = false
    @Published var activeSessionID: String?
    @Published var latestScreenshot: NSImage?
    @Published var isCapturing = false
    @Published var isRunningTest = false
    @Published var testLog: [TestLogEntry] = []
    @Published var lastError: String?

    struct TestLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType

        enum LogType { case info, success, error, screenshot }
    }

    // MARK: - Configuration

    private let serverPort: Int
    private let isolatedTesterPath: String?
    private var serverProcess: Process?
    private var sessionAppPID: Int32?

    var serverBaseURL: String { "http://127.0.0.1:\(serverPort)" }

    init(port: Int = 7100) {
        self.serverPort = port
        self.isolatedTesterPath = Self.findIsolatedTester()
    }

    // MARK: - Find IsolatedTester

    private static func findIsolatedTester() -> String? {
        #if !APP_STORE
        let candidates = [
            // Built from source
            NSHomeDirectory() + "/Desktop/IsolatedTester/.build/debug/isolated-http",
            NSHomeDirectory() + "/Desktop/IsolatedTester/.build/release/isolated-http",
            // Installed globally
            "/usr/local/bin/isolated-http",
            NSHomeDirectory() + "/.local/bin/isolated-http",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        #else
        return nil
        #endif
    }

    // MARK: - Server Lifecycle

    /// Start the IsolatedTester HTTP server.
    func startServer() async throws {
        guard let path = isolatedTesterPath else {
            throw SelfTestError.serverNotFound(
                "IsolatedTester not found. Build it at ~/Desktop/IsolatedTester with 'swift build'"
            )
        }

        // Check if already running
        if await checkServerHealth() {
            isServerRunning = true
            log("Server already running on port \(serverPort)", type: .info)
            return
        }

        #if !APP_STORE
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        var env = ProcessInfo.processInfo.environment
        env["IST_PORT"] = "\(serverPort)"
        process.environment = env

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        self.serverProcess = process
        #else
        throw SelfTestError.serverStartFailed("Self-testing is not available in the App Store build.")
        #endif

        // Wait for server to come up (up to 5 seconds)
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if await checkServerHealth() {
                isServerRunning = true
                log("IsolatedTester server started on port \(serverPort)", type: .success)
                return
            }
        }

        throw SelfTestError.serverStartFailed("Server did not respond after 5 seconds")
    }

    /// Stop the HTTP server and clean up sessions.
    func stopServer() {
        if let sessionID = activeSessionID {
            Task { try? await stopSession(sessionID) }
        }
        serverProcess?.terminate()
        serverProcess = nil
        isServerRunning = false
        activeSessionID = nil
        log("Server stopped", type: .info)
    }

    // MARK: - Session Management

    /// Create a test session by launching the app on a virtual display.
    func createSession(appPath: String, width: Int = 1440, height: Int = 900) async throws -> String {
        let body: [String: Any] = [
            "appPath": appPath,
            "displayWidth": width,
            "displayHeight": height,
        ]

        let data = try await httpPost(path: "/sessions", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionId"] as? String else {
            throw SelfTestError.invalidResponse("Failed to create session")
        }

        let pid = json["appPID"] as? Int32 ?? 0
        self.sessionAppPID = pid
        activeSessionID = sessionId
        log("Session \(sessionId) created (PID: \(pid))", type: .success)

        return sessionId
    }

    /// Stop and clean up a session.
    func stopSession(_ sessionId: String) async throws {
        _ = try await httpDelete(path: "/sessions/\(sessionId)")
        if activeSessionID == sessionId {
            activeSessionID = nil
            latestScreenshot = nil
        }
        log("Session \(sessionId) stopped", type: .info)
    }

    // MARK: - Screenshot

    /// Capture a screenshot from the virtual display.
    func captureScreenshot() async throws -> NSImage {
        guard let sessionId = activeSessionID else {
            throw SelfTestError.noActiveSession
        }

        isCapturing = true
        defer { isCapturing = false }

        let data = try await httpPost(
            path: "/sessions/\(sessionId)/screenshot",
            body: ["format": "png"]
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64 = json["base64Data"] as? String,
              let imageData = Data(base64Encoded: base64),
              let image = NSImage(data: imageData) else {
            throw SelfTestError.invalidResponse("Failed to decode screenshot")
        }

        latestScreenshot = image
        log("Screenshot captured (\(json["width"] ?? "?")x\(json["height"] ?? "?"))", type: .screenshot)

        return image
    }

    // MARK: - Actions

    /// Send a click action to the app on the virtual display.
    func click(x: Double, y: Double) async throws {
        guard let sessionId = activeSessionID else { throw SelfTestError.noActiveSession }
        _ = try await httpPost(
            path: "/sessions/\(sessionId)/action",
            body: ["action": "click", "x": x, "y": y]
        )
        log("Click at (\(Int(x)), \(Int(y)))", type: .info)
    }

    /// Send a type action.
    func typeText(_ text: String) async throws {
        guard let sessionId = activeSessionID else { throw SelfTestError.noActiveSession }
        _ = try await httpPost(
            path: "/sessions/\(sessionId)/action",
            body: ["action": "type", "text": text]
        )
        log("Type: \"\(text.prefix(50))\"", type: .info)
    }

    /// Send a key press with optional modifiers.
    func keyPress(_ key: String, modifiers: [String] = []) async throws {
        guard let sessionId = activeSessionID else { throw SelfTestError.noActiveSession }
        var body: [String: Any] = ["action": "keyPress", "key": key]
        if !modifiers.isEmpty { body["modifiers"] = modifiers }
        _ = try await httpPost(path: "/sessions/\(sessionId)/action", body: body)
        let modStr = modifiers.isEmpty ? "" : " (\(modifiers.joined(separator: "+")))"
        log("Key: \(key)\(modStr)", type: .info)
    }

    // MARK: - AI Test

    /// Run an AI-driven test using Claude Code or API.
    func runAITest(objective: String, provider: String = "claude-code") async throws -> TestResult {
        guard let sessionId = activeSessionID else { throw SelfTestError.noActiveSession }

        isRunningTest = true
        log("Starting AI test: \(objective)", type: .info)
        defer { isRunningTest = false }

        let body: [String: Any] = [
            "objective": objective,
            "provider": provider,
            "maxSteps": 15,
        ]

        let data = try await httpPost(path: "/sessions/\(sessionId)/test", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SelfTestError.invalidResponse("Failed to parse test result")
        }

        let success = json["success"] as? Bool ?? false
        let summary = json["summary"] as? String ?? "No summary"
        let steps = json["stepCount"] as? Int ?? 0

        let result = TestResult(success: success, summary: summary, stepCount: steps)

        log("Test \(success ? "PASSED" : "FAILED"): \(summary) (\(steps) steps)", type: success ? .success : .error)

        return result
    }

    struct TestResult {
        let success: Bool
        let summary: String
        let stepCount: Int
    }

    // MARK: - Quick Self-Test Flow

    /// One-shot: start server, create session, screenshot, stop.
    /// Returns the screenshot for inspection.
    func quickVisualTest(appPath: String) async throws -> NSImage {
        try await startServer()
        let sessionId = try await createSession(appPath: appPath)

        // Wait for app to render
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let screenshot = try await captureScreenshot()

        // Clean up
        try await stopSession(sessionId)

        return screenshot
    }

    // MARK: - HTTP Helpers

    private func checkServerHealth() async -> Bool {
        guard let url = URL(string: "\(serverBaseURL)/health") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "ok" else { return false }
            return true
        } catch {
            return false
        }
    }

    private func httpPost(path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(serverBaseURL)\(path)") else {
            throw SelfTestError.invalidResponse("Bad URL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SelfTestError.serverError(httpResponse.statusCode, errorText)
        }
        return data
    }

    private func httpDelete(path: String) async throws -> Data {
        guard let url = URL(string: "\(serverBaseURL)\(path)") else {
            throw SelfTestError.invalidResponse("Bad URL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: - Logging

    private func log(_ message: String, type: TestLogEntry.LogType) {
        testLog.append(TestLogEntry(timestamp: Date(), message: message, type: type))
        // Keep log manageable
        if testLog.count > 100 {
            testLog.removeFirst(testLog.count - 100)
        }
    }

    deinit {
        let process = serverProcess
        process?.terminate()
    }
}

// MARK: - Errors

enum SelfTestError: Error, LocalizedError {
    case serverNotFound(String)
    case serverStartFailed(String)
    case noActiveSession
    case invalidResponse(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .serverNotFound(let msg): return msg
        case .serverStartFailed(let msg): return "Server start failed: \(msg)"
        case .noActiveSession: return "No active test session"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        }
    }
}

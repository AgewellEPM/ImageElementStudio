import Foundation

@MainActor
final class SimulatorService: ObservableObject {

    // MARK: - Types

    struct SimulatorDevice: Identifiable, Hashable, Sendable {
        let id: String  // UDID
        let name: String
        let runtime: String
        let state: DeviceState
        let deviceTypeIdentifier: String

        enum DeviceState: String, Sendable {
            case shutdown = "Shutdown"
            case booted = "Booted"
            case shuttingDown = "Shutting Down"
            case unknown = "Unknown"

            init(rawString: String) {
                self = DeviceState(rawValue: rawString) ?? .unknown
            }
        }

        var isBooted: Bool { state == .booted }
    }

    // MARK: - Published State

    @Published var availableSimulators: [SimulatorDevice] = []
    @Published var selectedSimulatorID: String?
    @Published var lastScreenshotData: Data?
    @Published var isInstalling: Bool = false
    @Published var isLaunching: Bool = false

    // MARK: - List Simulators

    func listSimulators() async {
        let output = await runQuiet("xcrun simctl list devices available -j 2>/dev/null")
        guard let data = output.data(using: .utf8) else { return }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devices = json["devices"] as? [String: [[String: Any]]] else { return }

            var simulators: [SimulatorDevice] = []

            for (runtimeKey, deviceList) in devices {
                // Only include iOS runtimes
                guard runtimeKey.contains("iOS") else { continue }

                // Extract runtime version from key like "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
                let runtime = runtimeKey
                    .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                    .replacingOccurrences(of: "-", with: ".")
                    .replacingOccurrences(of: "iOS.", with: "iOS ")

                for device in deviceList {
                    guard let udid = device["udid"] as? String,
                          let name = device["name"] as? String,
                          let stateString = device["state"] as? String,
                          let isAvailable = device["isAvailable"] as? Bool,
                          isAvailable else { continue }

                    let deviceType = (device["deviceTypeIdentifier"] as? String) ?? ""

                    simulators.append(SimulatorDevice(
                        id: udid,
                        name: name,
                        runtime: runtime,
                        state: SimulatorDevice.DeviceState(rawString: stateString),
                        deviceTypeIdentifier: deviceType
                    ))
                }
            }

            // Sort: booted first, then by runtime descending, then by name
            availableSimulators = simulators.sorted { a, b in
                if a.isBooted != b.isBooted { return a.isBooted }
                if a.runtime != b.runtime { return a.runtime > b.runtime }
                return a.name < b.name
            }

        } catch {
            availableSimulators = []
        }
    }

    // MARK: - Smart Simulator Selection

    func bestAvailableSimulator() -> SimulatorDevice? {
        // 1. Already booted
        if let booted = availableSimulators.first(where: { $0.isBooted }) {
            return booted
        }

        // 2. Preferred device names in order
        let preferredNames = ["iPhone 16", "iPhone 16 Pro", "iPhone 15 Pro", "iPhone 15", "iPhone 14"]
        for name in preferredNames {
            if let device = availableSimulators.first(where: { $0.name == name }) {
                return device
            }
        }

        // 3. Any iPhone
        if let anyiPhone = availableSimulators.first(where: { $0.name.hasPrefix("iPhone") }) {
            return anyiPhone
        }

        // 4. Anything
        return availableSimulators.first
    }

    // MARK: - Boot Simulator

    func bootSimulator(udid: String) async -> Bool {
        let (exitCode, _) = await runCommand("xcrun simctl boot \(udid) 2>&1")
        // Exit code 149 means already booted - that's fine
        let success = exitCode == 0 || exitCode == 149

        if success {
            // Open Simulator.app
            _ = await runCommand("open -a Simulator 2>/dev/null")
            selectedSimulatorID = udid

            // Refresh device list to update state
            await listSimulators()
        }

        return success
    }

    // MARK: - Install App

    func installApp(simulatorID: String, appPath: String) async -> Bool {
        isInstalling = true
        defer { isInstalling = false }

        let (exitCode, _) = await runCommand("xcrun simctl install \(simulatorID) \(shellEscape(appPath)) 2>&1")
        return exitCode == 0
    }

    // MARK: - Launch App

    func launchApp(simulatorID: String, bundleID: String) async -> Bool {
        isLaunching = true
        defer { isLaunching = false }

        let (exitCode, _) = await runCommand("xcrun simctl launch \(simulatorID) \(bundleID) 2>&1")
        return exitCode == 0
    }

    // MARK: - Terminate App

    func terminateApp(simulatorID: String, bundleID: String) async {
        _ = await runCommand("xcrun simctl terminate \(simulatorID) \(bundleID) 2>/dev/null")
    }

    // MARK: - Take Screenshot

    func takeScreenshot(simulatorID: String) async -> Data? {
        let tempPath = NSTemporaryDirectory() + "ImageElementStudio-sim-screenshot-\(UUID().uuidString).png"
        let (exitCode, _) = await runCommand("xcrun simctl io \(simulatorID) screenshot --type=png \(shellEscape(tempPath)) 2>&1")

        guard exitCode == 0 else { return nil }

        let url = URL(fileURLWithPath: tempPath)
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)

        if let data {
            lastScreenshotData = data
        }

        return data
    }

    // MARK: - Shutdown

    func shutdownSimulator(udid: String) async {
        _ = await runCommand("xcrun simctl shutdown \(udid) 2>/dev/null")
        if selectedSimulatorID == udid {
            selectedSimulatorID = nil
        }
        await listSimulators()
    }

    // MARK: - Private Helpers

    private func runQuiet(_ command: String) async -> String {
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
    }

    private func runCommand(_ command: String) async -> (exitCode: Int32, output: String) {
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
    }

    private func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

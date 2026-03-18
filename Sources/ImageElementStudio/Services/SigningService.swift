import Foundation
import os

@MainActor
final class SigningService: ObservableObject {

    struct SigningIdentityInfo: Identifiable, Hashable, Sendable {
        let id: String          // SHA-1 hash
        let name: String        // "Apple Development: Luke (XXXXXXXXXX)"
        let type: IdentityType
        let teamID: String      // extracted from name or empty
        let isValid: Bool

        enum IdentityType: String, Sendable, Hashable {
            case development
            case distribution
            case developerID
            case unknown
        }
    }

    private let logger = Logger(subsystem: AppLogger.subsystem, category: "signing")

    @Published var availableIdentities: [SigningIdentityInfo] = []
    @Published var isDetecting: Bool = false
    @Published var detectionError: String?

    /// Detect code signing identities by parsing `security find-identity -v -p codesigning`
    func detectSigningIdentities() async {
        isDetecting = true
        detectionError = nil
        defer { isDetecting = false }

        do {
            let output = try await runProcess("/usr/bin/security", arguments: ["find-identity", "-v", "-p", "codesigning"])
            availableIdentities = parseIdentities(from: output)
            logger.info("Detected \(self.availableIdentities.count) signing identities")
        } catch {
            detectionError = "Failed to detect signing identities: \(error.localizedDescription)"
            logger.error("Signing identity detection failed: \(error.localizedDescription)")
        }
    }

    /// Parse the output of `security find-identity` into structured identity info
    func parseIdentities(from output: String) -> [SigningIdentityInfo] {
        // Each valid line looks like:
        // 1) ABC123DEF456... "Apple Development: Luke (TEAMID)"
        var results: [SigningIdentityInfo] = []
        let lines = output.components(separatedBy: "\n")

        let pattern = #"^\s*\d+\)\s+([A-F0-9]+)\s+"(.+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }

            guard let hashRange = Range(match.range(at: 1), in: line),
                  let nameRange = Range(match.range(at: 2), in: line) else { continue }

            let hash = String(line[hashRange])
            let name = String(line[nameRange])

            let type = classifyIdentity(name)
            let teamID = extractTeamID(from: name)

            results.append(SigningIdentityInfo(
                id: hash,
                name: name,
                type: type,
                teamID: teamID,
                isValid: true
            ))
        }

        return results
    }

    /// Save signing configuration to Keychain
    func saveSigningConfig(_ config: SigningConfiguration) {
        if !config.teamID.isEmpty {
            try? KeychainService.storeRaw(config.teamID, for: "deployment-team-id")
        }
        if !config.signingIdentity.isEmpty {
            try? KeychainService.storeRaw(config.signingIdentity, for: "deployment-signing-identity")
        }
    }

    /// Load signing configuration from Keychain
    func loadSigningConfig() -> SigningConfiguration? {
        guard let teamID = KeychainService.retrieveRaw(for: "deployment-team-id"),
              let identity = KeychainService.retrieveRaw(for: "deployment-signing-identity") else {
            return nil
        }
        return SigningConfiguration(teamID: teamID, signingIdentity: identity, codeSignStyle: "Automatic")
    }

    // MARK: - Private Helpers

    private func classifyIdentity(_ name: String) -> SigningIdentityInfo.IdentityType {
        if name.contains("Developer ID Application") || name.contains("Developer ID Installer") {
            return .developerID
        } else if name.contains("Apple Distribution") || name.contains("iPhone Distribution") || name.contains("3rd Party Mac Developer") {
            return .distribution
        } else if name.contains("Apple Development") || name.contains("iPhone Developer") || name.contains("Mac Developer") {
            return .development
        }
        return .unknown
    }

    private func extractTeamID(from name: String) -> String {
        // Pattern: "... (TEAMID)" at end of identity name
        let pattern = #"\(([A-Z0-9]{10})\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else {
            return ""
        }
        return String(name[range])
    }

    private func runProcess(_ path: String, arguments: [String]) async throws -> String {
        #if !APP_STORE
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        throw NSError(domain: "SigningService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Signing identity detection is not available in the App Store build. Use Xcode's automatic signing instead."])
        #endif
    }
}

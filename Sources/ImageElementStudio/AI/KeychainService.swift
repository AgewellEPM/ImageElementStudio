import Foundation
import os
import Security

struct KeychainService {
    static let serviceName = "com.imageelementstudio.apikeys"

    private static let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "KeychainService"
    )

    enum KeyName: String, CaseIterable {
        case anthropicAPIKey = "anthropic-api-key"
        case openaiAPIKey = "openai-api-key"
    }

    // Store a key value in the Keychain
    static func store(key: KeyName, value: String) throws {
        // Validate API key format before storing
        guard InputValidator.isAPIKeyFormatValid(value) else {
            logger.warning("Rejected API key storage for \(key.rawValue, privacy: .public): invalid format")
            throw KeychainError.invalidKeyFormat
        }

        // Delete existing entry first; failure is expected when no prior entry exists.
        try? delete(key: key)

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            AppLogger.error("Keychain store failed for \(key.rawValue): OSStatus \(status)", category: .security)
            throw KeychainError.storeFailed(status)
        }
        AppLogger.info("Keychain key stored successfully: \(key.rawValue)", category: .security)
    }

    // Retrieve a key value from the Keychain
    static func retrieve(key: KeyName) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else {
            return nil
        }

        return string
    }

    // Delete a key from the Keychain
    static func delete(key: KeyName) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            AppLogger.error("Keychain delete failed for \(key.rawValue): OSStatus \(status)", category: .security)
            throw KeychainError.deleteFailed(status)
        }
        AppLogger.debug("Keychain key deleted: \(key.rawValue)", category: .security)
    }

    // Resolve API key with fallback chain: Keychain → Environment (dev-only)
    static func resolveAPIKey(for key: KeyName) -> String? {
        // 1. Keychain (primary and only persistent storage)
        if let value = retrieve(key: key) {
            AppLogger.debug("API key resolved from Keychain: \(key.rawValue)", category: .security)
            return value
        }

        let envKey: String
        switch key {
        case .anthropicAPIKey:
            envKey = "ANTHROPIC_API_KEY"
        case .openaiAPIKey:
            envKey = "OPENAI_API_KEY"
        }

        // 2. Environment variable — dev/CI only, not persisted
        if let value = ProcessInfo.processInfo.environment[envKey], !value.isEmpty {
            AppLogger.debug("API key resolved from environment: \(key.rawValue)", category: .security)
            return value
        }

        AppLogger.warning("No API key found for \(key.rawValue)", category: .security)
        return nil
    }

    // MARK: - One-Time Migration from UserDefaults

    /// Migrates any API keys that were previously stored in UserDefaults into
    /// the Keychain, then removes them from UserDefaults. This should be called
    /// once at app launch to ensure a seamless transition for existing users.
    static func migrateKeysFromUserDefaultsIfNeeded() {
        let migrationFlag = "KeychainService.migrationCompleted"
        guard !UserDefaults.standard.bool(forKey: migrationFlag) else { return }

        AppLogger.info("Starting API key migration from UserDefaults to Keychain", category: .security)

        for keyName in KeyName.allCases {
            let defaultsKey: String
            switch keyName {
            case .anthropicAPIKey:
                defaultsKey = "ANTHROPIC_API_KEY"
            case .openaiAPIKey:
                defaultsKey = "OPENAI_API_KEY"
            }

            // Only migrate if there is a value in UserDefaults and nothing in Keychain yet
            if let value = UserDefaults.standard.string(forKey: defaultsKey),
               !value.isEmpty,
               retrieve(key: keyName) == nil {
                try? store(key: keyName, value: value)
            }

            // Always remove the key from UserDefaults regardless
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        AppLogger.info("API key migration from UserDefaults completed", category: .security)
        UserDefaults.standard.set(true, forKey: migrationFlag)
    }

    enum KeychainError: LocalizedError {
        case encodingFailed
        case storeFailed(OSStatus)
        case deleteFailed(OSStatus)
        case invalidKeyFormat

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode API key data."
            case .storeFailed(let status):
                return "Keychain store failed with status \(status)."
            case .deleteFailed(let status):
                return "Keychain delete failed with status \(status)."
            case .invalidKeyFormat:
                return "API key format is invalid. Keys must be at least 20 characters and contain only alphanumeric characters, hyphens, or underscores."
            }
        }
    }
}

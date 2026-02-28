import Foundation
import Security

struct KeychainService {
    static let serviceName = "com.imageelementstudio.apikeys"

    enum KeyName: String, CaseIterable {
        case anthropicAPIKey = "anthropic-api-key"
        case openaiAPIKey = "openai-api-key"
    }

    // Store a key value in the Keychain
    static func store(key: KeyName, value: String) throws {
        // Delete existing first
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
            throw KeychainError.storeFailed(status)
        }
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
            throw KeychainError.deleteFailed(status)
        }
    }

    // Resolve API key with fallback chain: Keychain → UserDefaults → Environment
    static func resolveAPIKey(for key: KeyName) -> String? {
        // 1. Keychain
        if let value = retrieve(key: key) {
            return value
        }

        // 2. UserDefaults
        let defaultsKey: String
        switch key {
        case .anthropicAPIKey:
            defaultsKey = "ANTHROPIC_API_KEY"
        case .openaiAPIKey:
            defaultsKey = "OPENAI_API_KEY"
        }
        if let value = UserDefaults.standard.string(forKey: defaultsKey), !value.isEmpty {
            return value
        }

        // 3. Environment variable
        if let value = ProcessInfo.processInfo.environment[defaultsKey], !value.isEmpty {
            return value
        }

        return nil
    }

    enum KeychainError: LocalizedError {
        case encodingFailed
        case storeFailed(OSStatus)
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode API key data."
            case .storeFailed(let status):
                return "Keychain store failed with status \(status)."
            case .deleteFailed(let status):
                return "Keychain delete failed with status \(status)."
            }
        }
    }
}

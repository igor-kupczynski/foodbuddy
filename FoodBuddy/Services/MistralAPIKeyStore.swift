import Foundation
import Security

protocol MistralAPIKeyStoring: Sendable {
    func apiKey() throws -> String?
    func setAPIKey(_ key: String?) throws
}

struct KeychainMistralAPIKeyStore: MistralAPIKeyStoring {
    enum Error: Swift.Error, LocalizedError {
        case keychainFailure(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychainFailure(let status):
                if status == errSecMissingEntitlement {
                    return "Keychain access is missing entitlements for this build."
                }

                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return "Keychain error (\(status)): \(message)"
                }

                return "Keychain error (\(status))."
            }
        }
    }

    let service: String
    let account: String

    init(service: String, account: String = "mistral_api_key") {
        self.service = service
        self.account = account
    }

    func apiKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                try? deleteAPIKey()
                return nil
            }
            guard let value = String(data: data, encoding: .utf8) else {
                // Heal a corrupted/non-text key entry and treat as missing key.
                try? deleteAPIKey()
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw Error.keychainFailure(status: status)
        }
    }

    func setAPIKey(_ key: String?) throws {
        let normalized = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            try deleteAPIKey()
            return
        }

        let data = Data(normalized.utf8)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                attributesToUpdate as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw Error.keychainFailure(status: updateStatus)
            }
            return
        }

        throw Error.keychainFailure(status: addStatus)
    }

    private func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.keychainFailure(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

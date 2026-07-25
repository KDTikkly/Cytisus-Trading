import Foundation
import Security

enum ModelSecretStoreError: Error {
    case invalidSecret
    case duplicateReference
    case notFound
    case platformFailure(OSStatus)
    case invalidEncoding
}

final class KeychainModelSecretStore: ModelSecretStore {
    private let service = "com.cytisus.trading.model-provider"

    func save(secret: String, reference: String) throws {
        guard !secret.isEmpty, let data = secret.data(using: .utf8) else {
            throw ModelSecretStoreError.invalidSecret
        }
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: reference,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ] as CFDictionary, nil)
        if status == errSecDuplicateItem {
            throw ModelSecretStoreError.duplicateReference
        }
        guard status == errSecSuccess else {
            throw ModelSecretStoreError.platformFailure(status)
        }
    }

    func replace(secret: String, reference: String) throws {
        guard !secret.isEmpty, let data = secret.data(using: .utf8) else {
            throw ModelSecretStoreError.invalidSecret
        }
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: reference
        ] as CFDictionary
        let status = SecItemUpdate(
            query,
            [kSecValueData: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            try save(secret: secret, reference: reference)
            return
        }
        guard status == errSecSuccess else {
            throw ModelSecretStoreError.platformFailure(status)
        }
    }

    func retrieve(reference: String) throws -> String {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: reference,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        if status == errSecItemNotFound {
            throw ModelSecretStoreError.notFound
        }
        guard status == errSecSuccess else {
            throw ModelSecretStoreError.platformFailure(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw ModelSecretStoreError.invalidEncoding
        }
        return value
    }

    func delete(reference: String) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: reference
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ModelSecretStoreError.platformFailure(status)
        }
    }
}

final class InMemoryModelSecretStore: ModelSecretStore {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func save(secret: String, reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !secret.isEmpty else {
            throw ModelSecretStoreError.invalidSecret
        }
        guard values[reference] == nil else {
            throw ModelSecretStoreError.duplicateReference
        }
        values[reference] = secret
    }

    func replace(secret: String, reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !secret.isEmpty else {
            throw ModelSecretStoreError.invalidSecret
        }
        values[reference] = secret
    }

    func retrieve(reference: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[reference] else {
            throw ModelSecretStoreError.notFound
        }
        return value
    }

    func delete(reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: reference)
    }
}

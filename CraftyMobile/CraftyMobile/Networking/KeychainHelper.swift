//
//  KeychainHelper.swift
//  CraftyMobile
//
//  Minimal Keychain wrapper for storing the API token securely. We deliberately
//  keep the token *out* of UserDefaults (which is plain plist on disk) and out
//  of the app bundle.
//

import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.larsniet.CraftyMobile.apiToken"
    private static let account = "default"

    /// Stores (or clears, if `value` is nil/empty) the token.
    @discardableResult
    static func set(_ value: String?) -> Bool {
        // Always remove any existing item first so we don't accumulate duplicates.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            return true // treat clearing as success
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        // Token is only needed while the device is unlocked, and shouldn't sync.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

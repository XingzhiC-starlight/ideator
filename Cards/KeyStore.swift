import Foundation
import Security

/// The API key, an Anthropic key or an OpenAI key. Lives in the login Keychain (generic password,
/// service "Ideator", account "api-key"): never in code, in the card folder, or in user defaults.
/// One item holds the last key pasted; the "anthropic-api-key" item that earlier builds wrote is
/// not read. Read once at launch and cached; `set` is the only writer.
///
/// A scratch run gets `inKeychain: false`: the key lives in memory for that run only, starts empty,
/// and no Keychain call is ever made, so a verify run can't trigger macOS's access prompt for the
/// owner's key or touch it.
class KeyStore {
    private static let service = "Ideator"
    private static let account = "api-key"

    /// nil = no key: the app works fully, it just never requests summaries.
    private(set) var apiKey: String?

    var provider: Provider? { apiKey.map { Provider(key: $0) } }

    let inKeychain: Bool

    init(inKeychain: Bool) {
        self.inKeychain = inKeychain
        guard inKeychain else { return }
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            apiKey = String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Trims whitespace; an empty string deletes the key. Updates the Keychain, then the cache.
    /// Returns false if the Keychain refused the change.
    @discardableResult
    func set(_ key: String?) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard inKeychain else {
            apiKey = trimmed.isEmpty ? nil : trimmed
            return true
        }
        let status: OSStatus
        if trimmed.isEmpty {
            status = SecItemDelete(Self.baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { return false }
            apiKey = nil
            return true
        }
        let data = Data(trimmed.utf8)
        let update = SecItemUpdate(Self.baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = Self.baseQuery
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        } else {
            status = update
        }
        guard status == errSecSuccess else { return false }
        apiKey = trimmed
        return true
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

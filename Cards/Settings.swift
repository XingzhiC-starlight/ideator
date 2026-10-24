import AppKit
import Security

/// The Anthropic API key. Lives in the login Keychain (generic password, service "Ideator",
/// account "anthropic-api-key"): never in code, in the card folder, or in user defaults.
/// Read once at launch and cached; `set` is the only writer.
final class KeyStore {
    private static let service = "Ideator"
    private static let account = "anthropic-api-key"

    /// nil = no key: the app works fully, it just never requests summaries.
    private(set) var apiKey: String?

    init() {
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

/// "Settings…" from the menu bar menu: one secure field for the key, Save and Remove buttons,
/// and a line saying whether a key is stored. Calls `onChange` after the store changes so the
/// controller can start (or stop) summaries.
final class SettingsWindow: NSWindow {
    private let keys: KeyStore
    private let onChange: () -> Void
    private let field = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString: "")

    init(keys: KeyStore, onChange: @escaping () -> Void) {
        self.keys = keys
        self.onChange = onChange
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Ideator Settings"
        isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: "Anthropic API key")
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "sk-ant-…"
        field.target = self
        field.action = #selector(save)
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let remove = NSButton(title: "Remove Key", target: self, action: #selector(remove))
        let buttons = NSStackView(views: [remove, save])
        let stack = NSStackView(views: [label, field, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            status.widthAnchor.constraint(equalTo: field.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: field.trailingAnchor),
        ])
        contentView = content
        refreshStatus()
    }

    @objc private func save() {
        guard !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if keys.set(field.stringValue) {
            field.stringValue = ""
            onChange()
        } else {
            NSSound.beep()
        }
        refreshStatus()
    }

    @objc private func remove() {
        keys.set(nil)
        onChange()
        refreshStatus()
    }

    private func refreshStatus() {
        status.stringValue = keys.apiKey == nil
            ? "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”."
            : "A key is saved in your Keychain. Paste a new one to replace it."
    }
}

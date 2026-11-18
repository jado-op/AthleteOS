import CryptoKit
import Foundation
import Security

/// Encrypts the athlete's most private backups on the phone before they are
/// uploaded — evening reflections and goals (`mindset.`), pain and head
/// injury notes (`safety.`) and the Academy twin (`academyTwin.`). The server
/// only ever stores `{ "sealed": "<AES-GCM, base64>" }` for these.
///
/// The key is made on the phone and kept in the Keychain, synchronised with
/// the athlete's iCloud Keychain so their other phones can read it; it never
/// goes to our server. A phone without the key can't read the backup — it
/// keeps its own data and the sealed copy stays untouched.
public enum CloudSeal {
    /// Settings groups that are sealed (see `CloudSync.settingGroup(of:)`).
    static let sealedGroups: Set<String> = ["mindset", "safety", "academyTwin"]

    static func isSealed(documentKey key: String) -> Bool {
        guard key.hasPrefix("settings.") else { return false }
        return sealedGroups.contains(String(key.dropFirst("settings.".count)))
    }

    struct Envelope: Codable, Equatable {
        var sealed: String
    }

    /// The plain JSON, sealed into an envelope document.
    static func seal(_ json: Data, key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.seal(json, using: key), let combined = box.combined else { return nil }
        return try? JSONEncoder().encode(Envelope(sealed: combined.base64EncodedString()))
    }

    /// The plain JSON back from an envelope; nil when it isn't one or the key doesn't fit.
    static func open(_ document: Data, key: SymmetricKey) -> Data? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: document),
              let combined = Data(base64Encoded: envelope.sealed),
              let box = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func isEnvelope(_ document: Data) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: document)) != nil
    }

    // MARK: - The key

    private static let service = "com.studentathlete.app.backup"
    private static let account = "backupKey.v1"

    /// The backup key, made on first use. Nil only if the Keychain refuses.
    static func key(createIfMissing: Bool = true) -> SymmetricKey? {
        if let data = readKey() { return SymmetricKey(data: data) }
        guard createIfMissing else { return nil }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = readKey() { return SymmetricKey(data: existing) }
        return status == errSecSuccess ? key : nil
    }

    private static func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

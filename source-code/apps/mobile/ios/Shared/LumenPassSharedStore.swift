// LumenPassSharedStore.swift
//
// Thin helper shared between the main Runner app and the AutoFill
// credential provider extension. Credentials are persisted to a file
// inside the App Group shared container, encrypted using AES-GCM with
// a key that lives in the iOS keychain (access-group-scoped so the
// extension can read it too).

import Foundation
import CryptoKit
import Security

private func storeLog(_ message: String) {
    NSLog("[LumenPassSharedStore] %@", message)
}

public struct LumenPassCredential: Codable, Hashable {
    public let id: String
    public let title: String
    public let username: String
    public let password: String
    public let url: String
    public let otpAuthUrl: String?
    /// Base64-encoded PNG bytes for the exact icon the app rendered for this entry.
    public let iconPngBase64: String?
    /// Google favicon helper URL (matches Flutter `faviconUrlForWebsite`).
    public let faviconUrl: String?
    public let avatarInitials: String?
    public let avatarBackgroundArgb: Int?
    public let avatarForegroundArgb: Int?
    public let hasPasskey: Bool
    /// Base64url WebAuthn credential id (matches desktop extension storage).
    public let passkeyCredentialIdB64url: String?
    /// PKCS#8 PEM EC P-256 private key for assertions (same material as KDBX custom field).
    public let passkeyPrivateKeyPem: String?
    public let passkeyRpId: String?
    public let passkeyUserHandleB64url: String?

    enum CodingKeys: String, CodingKey {
        case id, title, username, password, url, otpAuthUrl
        case iconPngBase64, faviconUrl, avatarInitials, avatarBackgroundArgb, avatarForegroundArgb, hasPasskey
        case passkeyCredentialIdB64url, passkeyPrivateKeyPem, passkeyRpId, passkeyUserHandleB64url
    }

    public init(id: String,
                title: String,
                username: String,
                password: String,
                url: String,
                otpAuthUrl: String?,
                iconPngBase64: String? = nil,
                faviconUrl: String? = nil,
                avatarInitials: String? = nil,
                avatarBackgroundArgb: Int? = nil,
                avatarForegroundArgb: Int? = nil,
                hasPasskey: Bool = false,
                passkeyCredentialIdB64url: String? = nil,
                passkeyPrivateKeyPem: String? = nil,
                passkeyRpId: String? = nil,
                passkeyUserHandleB64url: String? = nil) {
        self.id = id
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.otpAuthUrl = otpAuthUrl
        self.iconPngBase64 = iconPngBase64
        self.faviconUrl = faviconUrl
        self.avatarInitials = avatarInitials
        self.avatarBackgroundArgb = avatarBackgroundArgb
        self.avatarForegroundArgb = avatarForegroundArgb
        self.hasPasskey = hasPasskey
        self.passkeyCredentialIdB64url = passkeyCredentialIdB64url
        self.passkeyPrivateKeyPem = passkeyPrivateKeyPem
        self.passkeyRpId = passkeyRpId
        self.passkeyUserHandleB64url = passkeyUserHandleB64url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        username = try c.decode(String.self, forKey: .username)
        password = try c.decode(String.self, forKey: .password)
        url = try c.decode(String.self, forKey: .url)
        otpAuthUrl = try c.decodeIfPresent(String.self, forKey: .otpAuthUrl)
        iconPngBase64 = try c.decodeIfPresent(String.self, forKey: .iconPngBase64)
        faviconUrl = try c.decodeIfPresent(String.self, forKey: .faviconUrl)
        avatarInitials = try c.decodeIfPresent(String.self, forKey: .avatarInitials)
        avatarBackgroundArgb = try c.decodeIfPresent(Int.self, forKey: .avatarBackgroundArgb)
        avatarForegroundArgb = try c.decodeIfPresent(Int.self, forKey: .avatarForegroundArgb)
        hasPasskey = try c.decodeIfPresent(Bool.self, forKey: .hasPasskey) ?? false
        passkeyCredentialIdB64url = try c.decodeIfPresent(String.self, forKey: .passkeyCredentialIdB64url)
        passkeyPrivateKeyPem = try c.decodeIfPresent(String.self, forKey: .passkeyPrivateKeyPem)
        passkeyRpId = try c.decodeIfPresent(String.self, forKey: .passkeyRpId)
        passkeyUserHandleB64url = try c.decodeIfPresent(String.self, forKey: .passkeyUserHandleB64url)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(username, forKey: .username)
        try c.encode(password, forKey: .password)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(otpAuthUrl, forKey: .otpAuthUrl)
        try c.encodeIfPresent(iconPngBase64, forKey: .iconPngBase64)
        try c.encodeIfPresent(faviconUrl, forKey: .faviconUrl)
        try c.encodeIfPresent(avatarInitials, forKey: .avatarInitials)
        try c.encodeIfPresent(avatarBackgroundArgb, forKey: .avatarBackgroundArgb)
        try c.encodeIfPresent(avatarForegroundArgb, forKey: .avatarForegroundArgb)
        try c.encode(hasPasskey, forKey: .hasPasskey)
        try c.encodeIfPresent(passkeyCredentialIdB64url, forKey: .passkeyCredentialIdB64url)
        try c.encodeIfPresent(passkeyPrivateKeyPem, forKey: .passkeyPrivateKeyPem)
        try c.encodeIfPresent(passkeyRpId, forKey: .passkeyRpId)
        try c.encodeIfPresent(passkeyUserHandleB64url, forKey: .passkeyUserHandleB64url)
    }
}

public enum LumenPassSharedStore {
    /// App Group identifier. Must match the entry in both entitlements files.
    public static let appGroup = "group.com.tranit.lumenpass"

    /// Suffix for the shared keychain access group (after `$(AppIdentifierPrefix)`).
    /// Must match the string after the Team ID in both entitlements files.
    public static let keychainAccessGroupSuffix = "com.tranit.lumenpass.shared"

    private static let cacheFileName = "autofill_credentials.enc"
    private static let keychainService = "com.tranit.lumenpass.autofill"
    private static let keychainAccount = "credential-cache-key"

    /// Set by the AutoFill extension before it asks iOS to foreground the host
    /// app. The Runner app clears this when it handles the unlock hand-off.
    public static let pendingAutofillUnlockKey = "pendingAutofillUnlock"

    public static func markPendingAutofillUnlock() {
        UserDefaults(suiteName: appGroup)?.set(true, forKey: pendingAutofillUnlockKey)
    }

    public static func consumePendingAutofillUnlock() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return false }
        let pending = defaults.bool(forKey: pendingAutofillUnlockKey)
        if pending {
            defaults.removeObject(forKey: pendingAutofillUnlockKey)
        }
        return pending
    }

    /// Full keychain access group string, including Team ID prefix. Must match
    /// `keychain-access-groups` in entitlements exactly (what `SecItem*` expects).
    private static func resolvedKeychainAccessGroup() -> String {
        if let full = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String {
            let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
           !prefix.isEmpty {
            return "\(prefix)\(keychainAccessGroupSuffix)"
        }
        storeLog(
            "resolvedKeychainAccessGroup: add KeychainAccessGroup to Info.plist " +
            "(e.g. $(AppIdentifierPrefix)\(keychainAccessGroupSuffix)) so the extension " +
            "can read the same key as the host app."
        )
        return keychainAccessGroupSuffix
    }

    // MARK: - Public API

    /// Writes the provided credentials to the shared container.
    public static func save(credentials: [LumenPassCredential]) throws {
        let payload = try JSONEncoder().encode(credentials)
        let key: SymmetricKey
        do {
            key = try loadOrCreateKey()
        } catch {
            storeLog("save: loadOrCreateKey failed: \(error) – most likely the Keychain Sharing entitlement is missing from the provisioning profile for access group '\(resolvedKeychainAccessGroup())'")
            throw error
        }
        let sealed = try AES.GCM.seal(payload, using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "LumenPassSharedStore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to seal credentials."])
        }
        try writeToSharedContainer(data: combined)
        storeLog("save: wrote \(credentials.count) credentials (\(combined.count) bytes) to shared container at \(sharedFileURL()?.path ?? "<unknown>")")
    }

    /// Reads and decrypts the credentials from the shared container.
    /// Returns an empty array when there is nothing cached.
    public static func load() -> [LumenPassCredential] {
        guard let data = readFromSharedContainer() else {
            storeLog("load: shared container file missing")
            return []
        }
        let key: SymmetricKey
        do {
            key = try loadKey()
        } catch {
            storeLog("load: keychain key unavailable: \(error)")
            return []
        }
        guard let sealed = try? AES.GCM.SealedBox(combined: data) else {
            storeLog("load: ciphertext is not a valid AES-GCM sealed box (\(data.count) bytes)")
            return []
        }
        let decrypted: Data
        do {
            decrypted = try AES.GCM.open(sealed, using: key)
        } catch {
            storeLog("load: AES-GCM open failed (key mismatch?): \(error)")
            if let url = sharedFileURL() {
                try? FileManager.default.removeItem(at: url)
                storeLog("load: removed stale AutoFill cache; open LumenPass and unlock once to sync again")
            }
            return []
        }
        let result = (try? JSONDecoder().decode([LumenPassCredential].self, from: decrypted)) ?? []
        storeLog("load: decoded \(result.count) credentials")
        return result
    }

    /// Clears the cached credentials and destroys the encryption key.
    public static func clear() {
        if let url = sharedFileURL() {
            try? FileManager.default.removeItem(at: url)
        }
        deleteKey()
    }

    // MARK: - Shared file

    private static func sharedFileURL() -> URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        return base.appendingPathComponent(cacheFileName)
    }

    private static func writeToSharedContainer(data: Data) throws {
        guard let url = sharedFileURL() else {
            storeLog("writeToSharedContainer: App Group container unavailable – verify that '\(appGroup)' is listed in both entitlement files AND enabled on the App ID in the developer portal")
            throw NSError(domain: "LumenPassSharedStore", code: -2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "App Group container unavailable."])
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private static func readFromSharedContainer() -> Data? {
        guard let url = sharedFileURL(),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Keychain-backed AES key

    private static func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try? loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try storeKey(key)
        return key
    }

    private static func loadKey() throws -> SymmetricKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: resolvedKeychainAccessGroup(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
        _ = query // silence unused-warning in some toolchains
        return SymmetricKey(data: data)
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }

        // Delete any pre-existing item first. Use the identifier tuple only —
        // including `kSecValueData` here would turn it into a filter and the
        // delete would silently do nothing.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: resolvedKeychainAccessGroup(),
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: resolvedKeychainAccessGroup(),
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            storeLog("storeKey: SecItemAdd failed with OSStatus \(status) (errSecMissingEntitlement = -34018)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    private static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: resolvedKeychainAccessGroup(),
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Domain helpers

public extension LumenPassCredential {
    /// True when PEM + credential id + rp id are present so the AutoFill
    /// extension can complete a WebAuthn assertion (matches extension flow).
    var canSupplyPasskeyAssertion: Bool {
        guard hasPasskey else { return false }
        guard let pem = passkeyPrivateKeyPem?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pem.isEmpty else { return false }
        guard let cid = passkeyCredentialIdB64url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cid.isEmpty else { return false }
        guard let rp = passkeyRpId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rp.isEmpty else { return false }
        return true
    }

    /// Best-effort extraction of a host from a credential URL, used both to
    /// build `ASPasswordCredentialIdentity.serviceIdentifier` entries and to
    /// match fill requests coming from the OS.
    var serviceIdentifier: String {
        if url.isEmpty { return title }
        if let parsed = URL(string: url), let host = parsed.host, !host.isEmpty {
            return host.lowercased()
        }
        return url.lowercased()
    }
}

// MARK: - Base64url (WebAuthn / extension credential ids)

enum LumenPassBase64URL {
    static func decode(_ string: String) throws -> Data {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            throw NSError(domain: "LumenPassBase64URL", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Empty base64url"])
        }
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        if pad > 0 { s += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: s) else {
            throw NSError(domain: "LumenPassBase64URL", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid base64url"])
        }
        return data
    }
}

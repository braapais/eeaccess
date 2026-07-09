import Foundation

/// Tesla Fleet API region — determines the API host ("audience").
enum TeslaRegion: String, CaseIterable, Sendable {
    case eu
    case na

    var audience: String {
        switch self {
        case .eu: "https://fleet-api.prd.eu.vn.cloud.tesla.com"
        case .na: "https://fleet-api.prd.na.vn.cloud.tesla.com"
        }
    }

    var title: String {
        switch self {
        case .eu: "Europe"
        case .na: "North America"
        }
    }
}

/// Persisted, user-provided Tesla Fleet API credentials ("bring your own").
///
/// Each user registers their own app at developer.tesla.com and enters its
/// Client ID here, so no shared credential ships in the binary and each user's
/// own (usually free-tier) API usage is billed to them — not the developer.
/// Non-secret fields live in `UserDefaults`; the optional client secret is
/// kept in the Keychain (device-only).
struct TeslaFleetCredentialsStore {
    private let defaults = UserDefaults.standard
    private let clientIDKey = "TeslaFleet.clientID"
    private let regionKey = "TeslaFleet.region"
    private let redirectKey = "TeslaFleet.redirectURI"
    private let keychainService = (Bundle.main.bundleIdentifier ?? "com.elbaeverywhere.eeaccess") + ".teslafleet.secret"
    private let keychainAccount = "clientSecret"

    var clientID: String {
        get { defaults.string(forKey: clientIDKey) ?? "" }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey) }
    }

    var region: TeslaRegion {
        get { TeslaRegion(rawValue: defaults.string(forKey: regionKey) ?? "") ?? .eu }
        nonmutating set { defaults.set(newValue.rawValue, forKey: regionKey) }
    }

    var redirectURI: String {
        get { defaults.string(forKey: redirectKey) ?? "" }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: redirectKey) }
    }

    var clientSecret: String {
        get { keychainGet() ?? "" }
        nonmutating set { keychainSet(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Wipes the user's credentials (leaves region as a harmless preference).
    func clear() {
        defaults.removeObject(forKey: clientIDKey)
        defaults.removeObject(forKey: redirectKey)
        keychainSet("")
    }

    // MARK: - Keychain (client secret)

    private func keychainGet() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainSet(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

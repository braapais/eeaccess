import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Tesla Fleet API OAuth (Authorization Code + PKCE) for cloud control from
/// the iPhone. This is the "connect your Tesla account" half of the feature;
/// daily lock/unlock still happens over BLE on the watch.
///
/// Fully functional once ``TeslaFleetConfig`` is filled in with a Client ID
/// from developer.tesla.com. Tokens are stored in the Keychain (device-only).
@MainActor
@Observable
final class TeslaFleetAuth {
    enum Status: Equatable {
        case notConfigured
        case signedOut
        case connecting
        case signedIn
        case failed(String)
    }

    private(set) var status: Status = .notConfigured

    private let tokenStore = TokenStore()
    private let presenter = AuthPresentationProvider()
    private var authSession: ASWebAuthenticationSession?

    init() {
        reloadConfiguration()
    }

    /// Re-evaluates status after the user's credentials change (e.g. they just
    /// entered or cleared their own Client ID in the credentials screen).
    func reloadConfiguration() {
        if !TeslaFleetConfig.isConfigured {
            status = .notConfigured
        } else {
            status = tokenStore.load() != nil ? .signedIn : .signedOut
        }
    }

    var isSignedIn: Bool { status == .signedIn }

    /// Runs the interactive OAuth flow in a secure web session.
    func connect() async {
        guard TeslaFleetConfig.isConfigured else { status = .notConfigured; return }
        status = .connecting

        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.makeVerifier()

        var components = URLComponents(url: TeslaFleetConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: TeslaFleetConfig.clientID),
            .init(name: "redirect_uri", value: TeslaFleetConfig.redirectURI),
            .init(name: "scope", value: TeslaFleetConfig.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        do {
            let callbackURL = try await authenticate(url: components.url!)
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
            guard let code = items?.first(where: { $0.name == "code" })?.value else {
                throw AuthError.message("No authorization code returned")
            }
            guard items?.first(where: { $0.name == "state" })?.value == state else {
                throw AuthError.message("State mismatch — possible interception")
            }
            let tokens = try await exchange(code: code, verifier: verifier)
            tokenStore.save(tokens)
            status = .signedIn
        } catch is CancellationError {
            status = tokenStore.load() != nil ? .signedIn : .signedOut
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = tokenStore.load() != nil ? .signedIn : .signedOut
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func disconnect() {
        tokenStore.clear()
        status = TeslaFleetConfig.isConfigured ? .signedOut : .notConfigured
    }

    /// A valid access token + its expiry, for syncing to the watch so it can
    /// make cloud calls standalone. Refreshes first if near expiry.
    func sessionForSync() async -> (accessToken: String, expiresAt: Date)? {
        guard await validAccessToken() != nil, let tokens = tokenStore.load() else { return nil }
        return (tokens.accessToken, tokens.expiresAt)
    }

    /// Returns a valid access token, refreshing if it is near expiry. `nil` if
    /// signed out or refresh fails.
    func validAccessToken() async -> String? {
        guard var tokens = tokenStore.load() else { return nil }
        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }
        do {
            tokens = try await refresh(tokens)
            tokenStore.save(tokens)
            return tokens.accessToken
        } catch {
            status = .failed("Session expired — reconnect")
            return nil
        }
    }

    // MARK: - OAuth plumbing

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: TeslaFleetConfig.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AuthError.message("Authentication failed"))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
    }

    private func exchange(code: String, verifier: String) async throws -> TeslaTokens {
        var form: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": TeslaFleetConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": TeslaFleetConfig.redirectURI,
            "audience": TeslaFleetConfig.audience,
        ]
        if !TeslaFleetConfig.clientSecret.isEmpty {
            form["client_secret"] = TeslaFleetConfig.clientSecret
        }
        return try await postToken(form)
    }

    private func refresh(_ tokens: TeslaTokens) async throws -> TeslaTokens {
        var form: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": TeslaFleetConfig.clientID,
            "refresh_token": tokens.refreshToken,
        ]
        if !TeslaFleetConfig.clientSecret.isEmpty {
            form["client_secret"] = TeslaFleetConfig.clientSecret
        }
        var refreshed = try await postToken(form)
        // Tesla may omit a new refresh token; keep the existing one.
        if refreshed.refreshToken.isEmpty {
            refreshed.refreshToken = tokens.refreshToken
        }
        return refreshed
    }

    private func postToken(_ form: [String: String]) async throws -> TeslaTokens {
        var request = URLRequest(url: TeslaFleetConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.message("Token request failed: \(body)")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TeslaTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private enum AuthError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(m) = self { m } else { nil } }
    }
}

// MARK: - Tokens + storage

struct TeslaTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Minimal Keychain-backed store for the OAuth tokens (device-only).
private struct TokenStore {
    private let service = (Bundle.main.bundleIdentifier ?? "com.elbaeverywhere.eeaccess") + ".teslafleet"
    private let account = "tokens"

    func load() -> TeslaTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TeslaTokens.self, from: data)
    }

    func save(_ tokens: TeslaTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - PKCE

private enum PKCE {
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first
        guard let scene else {
            // The auth library only calls this method while actively presenting,
            // which requires the app to be foregrounded — i.e. at least one
            // window scene must exist. Crash with a clear message instead of
            // handing back a scene-less window that would fail silently.
            preconditionFailure("ASWebAuthenticationSession asked for a presentation anchor but no UIWindowScene is available.")
        }
        return scene.keyWindow ?? UIWindow(windowScene: scene)
    }
}

private extension CharacterSet {
    /// URL-query value encoding that escapes `+`, `&`, `=` etc.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?/")
        return set
    }()
}

import AuthenticationServices
import Foundation
import Observation
import UIKit

/// Drives the shared relay's server-mediated Tesla sign-in: opens Tesla's login
/// for the user, the RELAY (not this app) exchanges the resulting code — so the
/// one shared Client Secret never reaches the app binary — and auto-provisions
/// this device a random API key. No username or password anywhere in the flow.
///
/// iOS-only: watchOS has no `ASWebAuthenticationSession`. The watch receives
/// the resulting API key via WatchConnectivity sync (see `PhoneSyncService`).
@MainActor
@Observable
final class RelayAuth {
    enum Status: Equatable {
        case idle
        case connecting
        case failed(String)
    }

    private(set) var status: Status = .idle

    private let presenter = AuthPresentationProvider()
    private var authSession: ASWebAuthenticationSession?

    /// Runs the full sign-in dance and, on success, stores the resulting API
    /// key/user id in `relay.store` and flips it active.
    func connect(relay: RelayServerClient) async {
        status = .connecting
        do {
            let start = try await startOAuth()
            guard let authorizeURL = URL(string: start.authorizeUrl) else {
                throw AuthError.message("The relay returned a bad sign-in URL.")
            }
            let callbackURL = try await authenticate(url: authorizeURL)
            guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                  let code = items.first(where: { $0.name == "code" })?.value,
                  let state = items.first(where: { $0.name == "state" })?.value else {
                throw AuthError.message("No authorization code returned.")
            }
            let complete = try await completeOAuth(code: code, state: state)

            relay.store.apiKey = complete.apiKey
            relay.store.userId = complete.userId
            relay.store.enabled = true
            relay.reloadSettings()
            status = .idle
        } catch is CancellationError {
            status = .idle
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = .idle
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Relay OAuth endpoints

    private struct StartResponse: Decodable { let authorizeUrl: String; let state: String }
    private struct CompleteResponse: Decodable { let apiKey: String; let userId: String }

    private func startOAuth() async throws -> StartResponse {
        let url = URL(string: RelayServerConfig.baseURL + "/oauth/start")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.check(response)
        return try JSONDecoder().decode(StartResponse.self, from: data)
    }

    private func completeOAuth(code: String, state: String) async throws -> CompleteResponse {
        var request = URLRequest(url: URL(string: RelayServerConfig.baseURL + "/oauth/complete")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "state": state])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(CompleteResponse.self, from: data)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.message("Sign-in failed — try again.")
        }
    }

    // MARK: - ASWebAuthenticationSession

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: RelayServerConfig.callbackScheme
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

    private enum AuthError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(m) = self { m } else { nil } }
    }
}

private final class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first
        guard let scene else {
            preconditionFailure("ASWebAuthenticationSession asked for a presentation anchor but no UIWindowScene is available.")
        }
        return scene.keyWindow ?? UIWindow(windowScene: scene)
    }
}

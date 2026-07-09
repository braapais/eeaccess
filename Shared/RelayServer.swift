import Foundation
import Observation

/// Settings for the optional self-hosted relay server. When enabled, the app
/// sends cloud commands to your server (e.g. https://eeaccess.elbaeverywhere.com)
/// instead of Tesla directly — so a scheduled Unlock+Drive fires *server-side*
/// even when the phone/watch has no signal in a garage. Non-secret fields in
/// UserDefaults; the password in the Keychain (device-only).
struct RelayServerStore {
    private let defaults = UserDefaults.standard
    private let enabledKey = "Relay.enabled"
    private let baseKey = "Relay.baseURL"
    private let userKey = "Relay.username"
    private let keychainService = (Bundle.main.bundleIdentifier ?? "com.elbaeverywhere.eeaccess") + ".relay"
    private let keychainAccount = "password"

    var enabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: enabledKey) }
    }
    var baseURL: String {
        get { defaults.string(forKey: baseKey) ?? "" }
        nonmutating set {
            var v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.hasSuffix("/") { v.removeLast() }
            defaults.set(v, forKey: baseKey)
        }
    }
    var username: String {
        get { defaults.string(forKey: userKey) ?? "" }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userKey) }
    }
    var password: String {
        get { keychainGet() ?? "" }
        nonmutating set { keychainSet(newValue) }
    }

    /// Enabled and fully filled in.
    var isActive: Bool { enabled && !baseURL.isEmpty && !username.isEmpty }

    private func keychainGet() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
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

/// Talks to the self-hosted relay over HTTPS with Basic auth. Mirrors the cloud
/// command set plus server-side scheduling (`POST /vehicles/:vin/schedule`).
@MainActor
@Observable
final class RelayServerClient {
    struct Snapshot: Equatable {
        var batteryLevel: Int?
        var locked: Bool?
        var online: Bool?
        var insideTempC: Double?
    }
    struct RelayVehicle: Identifiable, Sendable, Equatable {
        let vin: String
        let displayName: String
        var id: String { vin }
    }
    struct PendingSchedule: Equatable {
        let id: Int
        let fireAt: Date
    }

    private(set) var snapshot: Snapshot?
    private(set) var accountVehicles: [RelayVehicle] = []
    private(set) var pendingSchedule: PendingSchedule?
    private(set) var isBusy = false
    private(set) var status: String?
    private(set) var lastError: String?

    let store = RelayServerStore()

    /// Observable mirror of the store's active flag, so SwiftUI reacts when
    /// settings are edited (iOS) or synced in (watch). Refresh via
    /// `reloadSettings()` after changing the store.
    private(set) var isActive = false

    init() { reloadSettings() }

    func reloadSettings() { isActive = store.isActive }

    // MARK: - Commands

    func fetchVehicles() async {
        await run("Loading…") {
            let d: VehicleListResponse = try await self.get("/vehicles")
            self.accountVehicles = d.response.map { RelayVehicle(vin: $0.vin, displayName: $0.display_name ?? "Tesla") }
        }
    }

    func refreshState(vin: String) async {
        await run("Refreshing…") {
            let d: VehicleDataResponse = try await self.get("/vehicles/\(vin)/state")
            self.snapshot = Snapshot(
                batteryLevel: d.response.charge_state?.battery_level,
                locked: d.response.vehicle_state?.locked,
                online: d.response.state.map { $0 == "online" },
                insideTempC: d.response.climate_state?.inside_temp
            )
        }
    }

    func wake(vin: String) async { await run("Waking…") { _ = try await self.post("/vehicles/\(vin)/wake") } }
    func unlock(vin: String) async { await run("Unlocking…") { _ = try await self.post("/vehicles/\(vin)/unlock") } }
    func lock(vin: String) async { await run("Locking…") { _ = try await self.post("/vehicles/\(vin)/lock") } }
    func drive(vin: String) async { await run("Enabling drive…") { _ = try await self.post("/vehicles/\(vin)/drive") } }
    func climateOn(vin: String) async { await run("Starting climate…") { _ = try await self.post("/vehicles/\(vin)/climate_on") } }
    func climateOff(vin: String) async { await run("Stopping climate…") { _ = try await self.post("/vehicles/\(vin)/climate_off") } }

    /// Schedules Unlock+Drive on the SERVER — fires even if this device goes
    /// offline. Returns the pending schedule for the countdown/cancel UI.
    func scheduleUnlockDrive(vin: String, delay: Int = 60) async {
        await run("Scheduling…") {
            let d: ScheduleResponse = try await self.post("/vehicles/\(vin)/schedule", body: ["delay": delay])
            self.pendingSchedule = PendingSchedule(id: d.id, fireAt: Date(timeIntervalSince1970: d.fireAt / 1000))
        }
    }

    func cancelSchedule() async {
        guard let id = pendingSchedule?.id else { return }
        await run("Cancelling…") {
            _ = try await self.delete("/schedules/\(id)")
            self.pendingSchedule = nil
        }
    }

    /// Reconciles the pending schedule with the server (it may have already
    /// fired or been set from another device).
    func refreshSchedules() async {
        guard isActive else { return }
        if let list: [ScheduleResponse] = try? await get("/schedules") {
            if let mine = list.first {
                pendingSchedule = PendingSchedule(id: mine.id, fireAt: Date(timeIntervalSince1970: mine.fireAt / 1000))
            } else {
                pendingSchedule = nil
            }
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        guard isActive else { lastError = "Relay server not configured."; return }
        isBusy = true; lastError = nil; status = label
        defer { isBusy = false }
        do { try await work(); status = "Done" }
        catch { lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; status = nil }
    }

    // MARK: - HTTP

    enum RelayError: LocalizedError {
        case notConfigured
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Relay server not configured."
            case let .http(code, body):
                code == 401 ? "Relay login rejected — check username/password." : "Relay error \(code): \(body)"
            }
        }
    }

    private func request(_ path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard !store.baseURL.isEmpty, let url = URL(string: store.baseURL + path) else { throw RelayError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        let creds = Data("\(store.username):\(store.password)".utf8).base64EncodedString()
        req.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "GET"))
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }
    @discardableResult
    private func post<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "POST", body: body))
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }
    @discardableResult
    private func post(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "POST", body: body))
        try Self.check(response, data)
        return data
    }
    @discardableResult
    private func delete(_ path: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "DELETE"))
        try Self.check(response, data)
        return data
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw RelayError.http(http.statusCode, String((String(data: data, encoding: .utf8) ?? "").prefix(160)))
        }
    }

    private struct VehicleListResponse: Decodable {
        struct V: Decodable { let vin: String; let display_name: String? }
        let response: [V]
    }
    private struct VehicleDataResponse: Decodable {
        struct Response: Decodable {
            let state: String?
            let charge_state: ChargeState?
            let vehicle_state: VehicleState?
            let climate_state: ClimateState?
        }
        struct ChargeState: Decodable { let battery_level: Int? }
        struct VehicleState: Decodable { let locked: Bool? }
        struct ClimateState: Decodable { let inside_temp: Double? }
        let response: Response
    }
    private struct ScheduleResponse: Decodable {
        let id: Int
        let vin: String
        let fireAt: Double
    }
}

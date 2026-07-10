import Foundation
import Observation

/// The shared, centrally-hosted EEAccess Tesla relay. Not user-editable —
/// there's exactly one, so there's nothing to type. It holds one shared Tesla
/// Developer app; each user's own Tesla sign-in is a separate session on the
/// server, identified by an auto-provisioned per-device API key.
enum RelayServerConfig {
    static let baseURL = "https://eeaccess.elbaeverywhere.com"
    /// Custom scheme the relay's OAuth bounce page redirects back into (see
    /// server.mjs's `/oauth/callback`). Distinct path from the direct BYOC
    /// flow's `eeaccess://tesla/callback` so the two can't be confused.
    static let callbackScheme = "eeaccess"
}

/// Local relay session state. No username or password: `apiKey` is a random
/// token auto-provisioned by the relay during Tesla sign-in (see `RelayAuth`
/// on iOS) and never chosen or typed by the user. Non-secret fields in
/// UserDefaults; the key itself in the Keychain (device-only).
struct RelayServerStore {
    private let defaults = UserDefaults.standard
    private let enabledKey = "Relay.enabled"
    private let userIdKey = "Relay.userId"
    private let keychainService = (Bundle.main.bundleIdentifier ?? "com.elbaeverywhere.eeaccess") + ".relay"
    private let keychainAccount = "apiKey"

    /// User-facing on/off switch — independent of whether they're registered,
    /// so they can pause using the relay without losing their server-side data.
    var enabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: enabledKey) }
    }
    /// Opaque id from the relay — not secret, just useful for support/debugging.
    var userId: String {
        get { defaults.string(forKey: userIdKey) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: userIdKey) }
    }
    var apiKey: String {
        get { keychainGet() ?? "" }
        nonmutating set { keychainSet(newValue) }
    }

    /// Registered (has a key) and switched on.
    var isActive: Bool { enabled && !apiKey.isEmpty }

    /// Wipes local relay state. Does NOT delete the server-side account — call
    /// `RelayServerClient.disconnect()` for that.
    func clear() {
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: userIdKey)
        keychainSet("")
    }

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

/// Talks to the shared relay over HTTPS with a Bearer API key. Mirrors the
/// cloud command set plus server-side scheduling (`POST /vehicles/:vin/schedule`),
/// which is the whole point: it fires even if this device is offline by then.
/// Works unmodified on iOS and watchOS — only the interactive sign-in
/// (`RelayAuth`, iOS-only) differs per platform.
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
    /// Pending schedules keyed by VIN — a schedule on one car must never be
    /// read/cancelled from another car's screen.
    private(set) var scheduledByVIN: [String: PendingSchedule] = [:]
    private(set) var isBusy = false
    private(set) var status: String?
    private(set) var lastError: String?

    func pendingSchedule(for vin: String) -> PendingSchedule? { scheduledByVIN[vin] }

    let store = RelayServerStore()

    /// Observable mirror of the store's active flag, so SwiftUI reacts when
    /// sign-in completes (iOS) or settings sync in (watch). Refresh via
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

    /// `wake_up` only REQUESTS a wake — Tesla can take up to ~30s to actually
    /// bring the car online, so a flat "Done" right after looks like nothing
    /// happened. Polls vehicle state afterward so the UI shows real progress.
    func wake(vin: String) async {
        guard !isBusy else { return }
        guard isActive else { lastError = "Connect to the relay first."; return }
        isBusy = true; lastError = nil; status = "Waking…"
        defer { isBusy = false }
        do {
            _ = try await self.post("/vehicles/\(vin)/wake")
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = nil
            return
        }
        await pollUntilAwake(vin: vin)
    }

    /// A 408 here just means "still asleep," so it's swallowed and retried
    /// rather than surfaced — only the final timeout is shown to the user.
    private func pollUntilAwake(vin: String, attempts: Int = 10) async {
        for attempt in 1...attempts {
            status = "Waking… (\(attempt * 3)s)"
            try? await Task.sleep(for: .seconds(3))
            guard let d: VehicleDataResponse = try? await self.get("/vehicles/\(vin)/state") else { continue }
            if d.response.state == "online" {
                snapshot = Snapshot(
                    batteryLevel: d.response.charge_state?.battery_level,
                    locked: d.response.vehicle_state?.locked,
                    online: true,
                    insideTempC: d.response.climate_state?.inside_temp
                )
                status = "Awake"
                return
            }
        }
        status = "Still asleep — try again in a moment"
    }

    func unlock(vin: String) async { await run("Unlocking…") { _ = try await self.post("/vehicles/\(vin)/unlock") } }
    func lock(vin: String) async { await run("Locking…") { _ = try await self.post("/vehicles/\(vin)/lock") } }
    func drive(vin: String) async { await run("Enabling drive…") { _ = try await self.post("/vehicles/\(vin)/drive") } }
    func climateOn(vin: String) async { await run("Starting climate…") { _ = try await self.post("/vehicles/\(vin)/climate_on") } }
    func climateOff(vin: String) async { await run("Stopping climate…") { _ = try await self.post("/vehicles/\(vin)/climate_off") } }

    /// Immediately unlocks then enables drive, back to back — no delay. The
    /// scheduled `scheduleUnlockDrive` below is for triggering ahead of time
    /// before losing signal; this is for when you're already at the car.
    func unlockAndDrive(vin: String) async {
        await run("Unlocking…") {
            _ = try await self.post("/vehicles/\(vin)/unlock")
            self.status = "Enabling drive…"
            _ = try await self.post("/vehicles/\(vin)/drive")
        }
    }

    /// Schedules Unlock+Drive on the SERVER — fires even if this device goes
    /// offline. Stores the pending schedule (keyed by VIN) for the
    /// countdown/cancel UI.
    func scheduleUnlockDrive(vin: String, delay: Int = 60) async {
        await run("Scheduling…") {
            let d: ScheduleResponse = try await self.post("/vehicles/\(vin)/schedule", body: ["delay": delay])
            self.scheduledByVIN[vin] = PendingSchedule(id: d.id, fireAt: Date(timeIntervalSince1970: d.fireAt / 1000))
        }
    }

    func cancelSchedule(vin: String) async {
        guard let id = scheduledByVIN[vin]?.id else { return }
        await run("Cancelling…") {
            _ = try await self.delete("/schedules/\(id)")
            self.scheduledByVIN[vin] = nil
        }
    }

    /// Reconciles all pending schedules with the server (one may have already
    /// fired, been cancelled, or been set from another device).
    func refreshSchedules() async {
        guard isActive else { return }
        if let list: [ScheduleResponse] = try? await get("/schedules") {
            var byVIN: [String: PendingSchedule] = [:]
            for s in list {
                byVIN[s.vin] = PendingSchedule(id: s.id, fireAt: Date(timeIntervalSince1970: s.fireAt / 1000))
            }
            scheduledByVIN = byVIN
        }
    }

    /// Deletes this account's data on the relay (best-effort) and always clears
    /// local credentials, even if the network call fails — a stuck local key
    /// should never linger just because the delete request didn't land.
    func disconnect() async {
        guard !isBusy else { return }
        isBusy = true; status = "Disconnecting…"
        defer { isBusy = false }
        if !store.apiKey.isEmpty {
            _ = try? await delete("/account")
        }
        store.clear()
        scheduledByVIN = [:]
        accountVehicles = []
        snapshot = nil
        lastError = nil
        status = nil
        reloadSettings()
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        guard isActive else { lastError = "Connect to the relay first."; return }
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
            case .notConfigured: "Not connected to the relay."
            case let .http(code, body):
                switch code {
                case 401: "Relay session invalid — reconnect in Settings."
                case 403: "That car isn't on your connected Tesla account."
                // The server forwards Tesla's upstream status; 408 is Tesla's
                // signal for an asleep/unreachable vehicle (see server.mjs).
                case 408: "Vehicle is asleep — tap Wake, then try again."
                case 429: "Too many requests — wait a moment and try again."
                default: "Relay error \(code): \(body)"
                }
            }
        }
    }

    private func request(_ path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: RelayServerConfig.baseURL + path) else { throw RelayError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !store.apiKey.isEmpty {
            req.setValue("Bearer \(store.apiKey)", forHTTPHeaderField: "Authorization")
        }
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

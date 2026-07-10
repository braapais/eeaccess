import Foundation
import Observation

/// Lightweight watch-side Tesla Fleet client for cloud cars (pre-2021 S/X that
/// have no BLE key). It calls the Fleet API directly using the access token +
/// region host the iPhone syncs over. It does NOT do interactive OAuth or token
/// refresh — those stay on the phone; if the synced token expires the watch
/// asks the user to open the iPhone app.
@MainActor
@Observable
final class WatchTeslaCloud {
    struct Snapshot: Equatable {
        var batteryLevel: Int?
        var locked: Bool?
        var online: Bool?
        var insideTempC: Double?
    }

    private(set) var snapshot: Snapshot?
    private(set) var isBusy = false
    private(set) var status: String?
    private(set) var lastError: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var baseURL: String?
    private var clientID: String?
    private var clientSecret: String?

    private let tokenEndpoint = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!

    /// A usable session exists (token present, host known).
    var hasSession: Bool { accessToken?.isEmpty == false && baseURL != nil }
    /// The synced token has expired.
    var tokenExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
    /// True if the watch has what it needs to refresh the token itself.
    var canRefresh: Bool {
        !(refreshToken?.isEmpty ?? true) && !(clientID?.isEmpty ?? true)
    }
    /// Whole hours the current token is still valid for (for a fresh indicator).
    var hoursRemaining: Int {
        guard let expiresAt else { return 0 }
        return max(0, Int(expiresAt.timeIntervalSinceNow / 3600))
    }

    /// Applies the session the iPhone synced (tokens, region host, credentials).
    func applySession(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        baseURL: String,
        clientID: String,
        clientSecret: String
    ) {
        // Config is always safe to adopt (latest edit on the phone wins).
        self.baseURL = baseURL
        self.clientID = clientID
        self.clientSecret = clientSecret

        // The (access, refresh, expiry) triple is only adopted together, and
        // only if the incoming session is actually newer. If the watch already
        // refreshed locally (ensureFreshToken()) it may hold a newer — possibly
        // rotated — refresh token; blindly overwriting it with the phone's
        // stale one would break the watch's NEXT refresh once Tesla invalidates
        // the rotated-out token.
        if let current = self.expiresAt, current >= expiresAt { return }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Refreshes the access token directly with Tesla over LTE/WiFi (no phone)
    /// when it's within 5 minutes of expiry. Called on app open and before
    /// each command. Returns whether a usable (non-expired) token is in hand.
    @discardableResult
    func ensureFreshToken() async -> Bool {
        guard let expiresAt else { return accessToken?.isEmpty == false }
        if Date() < expiresAt.addingTimeInterval(-300) { return true }   // >5 min left
        if await refresh() { return true }
        return Date() < expiresAt                                        // still valid?
    }

    /// Directly exchanges the refresh token for a new access token.
    @discardableResult
    func refresh() async -> Bool {
        guard let refreshToken, !refreshToken.isEmpty,
              let clientID, !clientID.isEmpty else { return false }
        var form = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
        if let clientSecret, !clientSecret.isEmpty { form["client_secret"] = clientSecret }
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            return false
        }
        accessToken = decoded.access_token
        expiresAt = Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        if let newRefresh = decoded.refresh_token, !newRefresh.isEmpty { self.refreshToken = newRefresh }
        return true
    }

    private struct RefreshResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    // MARK: - Commands

    func refreshState(vin: String) async {
        await run("Refreshing…") {
            let data: VehicleDataResponse = try await self.get("/api/1/vehicles/\(vin)/vehicle_data")
            self.snapshot = Snapshot(
                batteryLevel: data.response.charge_state?.battery_level,
                locked: data.response.vehicle_state?.locked,
                online: data.response.state.map { $0 == "online" },
                insideTempC: data.response.climate_state?.inside_temp
            )
        }
    }

    /// `wake_up` only REQUESTS a wake — Tesla can take up to ~30s to actually
    /// bring the car online, so a flat "Done" right after looks like nothing
    /// happened. Polls vehicle state afterward so the UI shows real progress.
    func wake(vin: String) async {
        guard !isBusy else { return }
        guard hasSession else { lastError = "Open EEAccess on your iPhone once to enable cloud control."; return }
        isBusy = true; lastError = nil; status = "Waking…"
        defer { isBusy = false }
        guard await ensureFreshToken() else {
            lastError = "Couldn't refresh your Tesla session — open EEAccess on your iPhone to reconnect."
            status = nil
            return
        }
        do {
            _ = try await self.post("/api/1/vehicles/\(vin)/wake_up")
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
            guard let data: VehicleDataResponse = try? await self.get("/api/1/vehicles/\(vin)/vehicle_data") else {
                continue
            }
            if data.response.state == "online" {
                snapshot = Snapshot(
                    batteryLevel: data.response.charge_state?.battery_level,
                    locked: data.response.vehicle_state?.locked,
                    online: true,
                    insideTempC: data.response.climate_state?.inside_temp
                )
                status = "Awake"
                return
            }
        }
        status = "Still asleep — try again in a moment"
    }

    // Only ever called for `.cloud`-mode vehicles (see WatchTeslaVehicleView),
    // which are exempt from Tesla's signed-command requirement — so every
    // command here is unsigned, unconditionally.
    func lock(vin: String) async { await command(vin, "door_lock", "Locking…") }
    func unlock(vin: String) async { await command(vin, "door_unlock", "Unlocking…") }
    func startDrive(vin: String) async { await command(vin, "remote_start_drive", "Enabling drive…") }
    func climateOn(vin: String) async { await command(vin, "auto_conditioning_start", "Starting climate…") }
    func climateOff(vin: String) async { await command(vin, "auto_conditioning_stop", "Stopping climate…") }

    /// Immediately unlocks then enables drive, back to back — no delay. The
    /// scheduled `scheduleUnlockDrive` below is for triggering ahead of time
    /// before losing signal; this is for when you're already at the car.
    func unlockAndDrive(vin: String) async {
        await run("Unlocking…") {
            _ = try await self.post("/api/1/vehicles/\(vin)/command/door_unlock")
            self.status = "Enabling drive…"
            _ = try await self.post("/api/1/vehicles/\(vin)/command/remote_start_drive")
        }
    }

    // MARK: - Scheduled (garage dead-zone) unlock + drive

    /// Seconds left on a scheduled Unlock & Drive, or nil if none is pending.
    private(set) var scheduledSeconds: Int?
    private var scheduleTask: Task<Void, Never>?

    /// Counts down `delay` seconds, then sends Unlock + Start Drive. Use it
    /// while you still have signal (before walking into a no-signal garage) so
    /// the car is unlocked and drive-enabled when you arrive. Retries a few
    /// times if the network blips at fire time.
    func scheduleUnlockDrive(vin: String, delay: Int = 60) {
        cancelSchedule()
        scheduleTask = Task { [weak self] in
            guard let self else { return }
            var remaining = delay
            while remaining > 0 {
                self.scheduledSeconds = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { self.scheduledSeconds = nil; return }
                remaining -= 1
            }
            self.scheduledSeconds = 0
            await self.fireUnlockDrive(vin: vin)
            self.scheduledSeconds = nil
        }
    }

    func cancelSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        scheduledSeconds = nil
    }

    private func fireUnlockDrive(vin: String) async {
        for attempt in 0..<3 {
            await unlock(vin: vin)
            await startDrive(vin: vin)
            if lastError == nil { return }
            if attempt < 2 { try? await Task.sleep(for: .seconds(5)) }
        }
    }

    private func command(_ vin: String, _ action: String, _ label: String) async {
        // Pre-2021 cars accept unsigned commands over the plain Fleet host,
        // which is the only path available on the watch (no signing proxy).
        await run(label) { _ = try await self.post("/api/1/vehicles/\(vin)/command/\(action)") }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        guard hasSession else { lastError = "Open EEAccess on your iPhone once to enable cloud control."; return }
        isBusy = true; lastError = nil; status = label
        defer { isBusy = false }
        guard await ensureFreshToken() else {
            lastError = "Couldn't refresh your Tesla session — open EEAccess on your iPhone to reconnect."
            status = nil
            return
        }
        do {
            try await work()
            status = "Done"
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = nil
        }
    }

    // MARK: - HTTP

    enum CloudError: LocalizedError {
        case noSession
        case asleep
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .noSession: "Not signed in on iPhone."
            case .asleep: "Vehicle is asleep — tap Wake, then try again."
            case let .http(code, body): "Fleet API error \(code): \(body)"
            }
        }
    }

    private func request(_ path: String, method: String) throws -> URLRequest {
        guard let baseURL, let token = accessToken, let url = URL(string: baseURL + path) else {
            throw CloudError.noSession
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "GET"))
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func post(_ path: String) async throws -> Data {
        var req = try request(path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data)
        return data
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 408 { throw CloudError.asleep }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.http(http.statusCode, String(body.prefix(160)))
        }
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
}

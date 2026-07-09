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
    private var expiresAt: Date?
    private var baseURL: String?

    /// A usable session exists (token present, host known).
    var hasSession: Bool { accessToken?.isEmpty == false && baseURL != nil }
    /// The synced token has expired — the phone needs to sync a fresh one.
    var tokenExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// Applies the session the iPhone synced (access token, expiry, region host).
    func applySession(accessToken: String, expiresAt: Date, baseURL: String) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.baseURL = baseURL
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

    func wake(vin: String) async {
        await run("Waking…") { _ = try await self.post("/api/1/vehicles/\(vin)/wake_up") }
    }

    func lock(vin: String, unsigned: Bool) async { await command(vin, "door_lock", "Locking…", unsigned) }
    func unlock(vin: String, unsigned: Bool) async { await command(vin, "door_unlock", "Unlocking…", unsigned) }
    func startDrive(vin: String, unsigned: Bool) async { await command(vin, "remote_start_drive", "Enabling drive…", unsigned) }
    func climateOn(vin: String, unsigned: Bool) async { await command(vin, "auto_conditioning_start", "Starting climate…", unsigned) }
    func climateOff(vin: String, unsigned: Bool) async { await command(vin, "auto_conditioning_stop", "Stopping climate…", unsigned) }

    private func command(_ vin: String, _ action: String, _ label: String, _ unsigned: Bool) async {
        // Pre-2021 cars accept unsigned commands over the plain Fleet host,
        // which is the only path available on the watch (no signing proxy).
        await run(label) { _ = try await self.post("/api/1/vehicles/\(vin)/command/\(action)") }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        guard hasSession else { lastError = "Open EEAccess on your iPhone to enable cloud control."; return }
        guard !tokenExpired else { lastError = "Session expired — open EEAccess on your iPhone to refresh."; return }
        isBusy = true; lastError = nil; status = label
        defer { isBusy = false }
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
        guard let baseURL, let token = accessToken else { throw CloudError.noSession }
        var request = URLRequest(url: URL(string: baseURL + path)!)
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

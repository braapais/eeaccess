import Foundation
import Observation

/// Tesla Fleet API REST client for cloud control: read state, wake, and —
/// through a signing proxy — lock/unlock/climate. Uses `TeslaFleetAuth` for
/// access tokens.
///
/// On 2021+ vehicles (incl. the 2023 Model X) commands must be end-to-end
/// signed. Reading state and waking work against Fleet API directly; lock /
/// unlock / climate are POSTed to `TeslaFleetConfig.commandBaseURL`, which
/// must point at Tesla's `tesla-http-proxy` for those to succeed.
///
/// Pre-2021 Model S/X are the exception: Tesla exempts them from the signed
/// command protocol, so passing `unsigned: true` sends lock/unlock/climate
/// straight to the Fleet API host — no proxy needed. That is the (only) way to
/// reach those cars, which have no BLE phone key.
@MainActor
@Observable
final class TeslaFleetService {
    struct Snapshot: Sendable, Equatable {
        var batteryLevel: Int?
        var locked: Bool?
        var online: Bool?
        var insideTempC: Double?
    }

    /// A vehicle as listed on the signed-in Tesla account.
    struct FleetVehicle: Identifiable, Sendable, Equatable {
        let vin: String
        let displayName: String
        var id: String { vin }
    }

    private(set) var snapshot: Snapshot?
    private(set) var accountVehicles: [FleetVehicle] = []
    /// The account's exact home-region API base, resolved from Tesla once
    /// signed in. Tesla routes user data per home region; the generic region
    /// host can return 412 if it isn't the exact match.
    private(set) var resolvedBaseURL: String?
    private(set) var isBusy = false
    private(set) var status: String?
    private(set) var lastError: String?

    enum FleetError: LocalizedError {
        case notSignedIn
        case signingRequired
        case asleep
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "Connect your Tesla account first."
            case .signingRequired:
                "This car needs signed commands. Point TeslaFleetConfig.commandBaseURL at your tesla-http-proxy to enable cloud lock/unlock."
            case .asleep:
                "Vehicle is asleep — tap Wake, then try again."
            case let .http(code, body):
                "Fleet API error \(code): \(body)"
            }
        }
    }

    // MARK: - Commands

    /// Loads the vehicles on the signed-in Tesla account so the user can pick
    /// one instead of typing a VIN (needs the `vehicle_device_data` scope).
    func fetchVehicles(auth: TeslaFleetAuth) async {
        await run("Loading your vehicles…") {
            let data: VehicleListResponse = try await self.get("/api/1/vehicles", auth: auth)
            self.accountVehicles = data.response.map {
                FleetVehicle(vin: $0.vin, displayName: $0.display_name ?? "Tesla")
            }
        }
    }

    func refresh(vin: String, auth: TeslaFleetAuth) async {
        await run("Refreshing…") {
            let data: VehicleDataResponse = try await self.get("/api/1/vehicles/\(vin)/vehicle_data", auth: auth)
            self.snapshot = Snapshot(
                batteryLevel: data.response.charge_state?.battery_level,
                locked: data.response.vehicle_state?.locked,
                online: data.response.state.map { $0 == "online" },
                insideTempC: data.response.climate_state?.inside_temp
            )
        }
    }

    func wake(vin: String, auth: TeslaFleetAuth) async {
        await run("Waking…") {
            _ = try await self.post("/api/1/vehicles/\(vin)/wake_up", auth: auth, command: false)
        }
    }

    /// - Parameter unsigned: pre-2021 Model S/X accept plain unsigned commands,
    ///   so we send them straight to the Fleet API and skip the signing proxy.
    ///   2021+ cars must be signed, so those route through
    ///   `TeslaFleetConfig.commandBaseURL`.
    func lock(vin: String, auth: TeslaFleetAuth, unsigned: Bool = false) async {
        await command(vin: vin, action: "door_lock", label: "Locking…", auth: auth, unsigned: unsigned)
    }

    func unlock(vin: String, auth: TeslaFleetAuth, unsigned: Bool = false) async {
        await command(vin: vin, action: "door_unlock", label: "Unlocking…", auth: auth, unsigned: unsigned)
    }

    func climateOn(vin: String, auth: TeslaFleetAuth, unsigned: Bool = false) async {
        await command(vin: vin, action: "auto_conditioning_start", label: "Starting climate…", auth: auth, unsigned: unsigned)
    }

    func climateOff(vin: String, auth: TeslaFleetAuth, unsigned: Bool = false) async {
        await command(vin: vin, action: "auto_conditioning_stop", label: "Stopping climate…", auth: auth, unsigned: unsigned)
    }

    /// Enables keyless driving (`remote_start_drive`) — the car allows driving
    /// for ~2 minutes; press the brake within the window. Cloud equivalent of
    /// the watch's Start Drive.
    func startDrive(vin: String, auth: TeslaFleetAuth, unsigned: Bool = false) async {
        await command(vin: vin, action: "remote_start_drive", label: "Enabling drive…", auth: auth, unsigned: unsigned)
    }

    // MARK: - Scheduled (garage dead-zone) unlock + drive

    /// Seconds left on a scheduled Unlock & Drive, or nil if none is pending.
    private(set) var scheduledSeconds: Int?
    private var scheduleTask: Task<Void, Never>?

    /// Counts down `delay` seconds, then sends Unlock + Start Drive — trigger it
    /// while you still have signal so the car is ready when you reach a
    /// no-signal garage. Retries a few times if the network blips at fire time.
    func scheduleUnlockDrive(vin: String, auth: TeslaFleetAuth, unsigned: Bool, delay: Int = 60) {
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
            for attempt in 0..<3 {
                await self.unlock(vin: vin, auth: auth, unsigned: unsigned)
                await self.startDrive(vin: vin, auth: auth, unsigned: unsigned)
                if self.lastError == nil { break }
                if attempt < 2 { try? await Task.sleep(for: .seconds(5)) }
            }
            self.scheduledSeconds = nil
        }
    }

    func cancelSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        scheduledSeconds = nil
    }

    private func command(vin: String, action: String, label: String, auth: TeslaFleetAuth, unsigned: Bool) async {
        await run(label) {
            // `command: true` routes to the signing proxy; for pre-2021 cars we
            // pass `command: false` to hit the Fleet API host directly, which
            // accepts the unsigned command.
            _ = try await self.post("/api/1/vehicles/\(vin)/command/\(action)", auth: auth, command: !unsigned)
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
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

    private func token(_ auth: TeslaFleetAuth) async throws -> String {
        guard let token = await auth.validAccessToken() else { throw FleetError.notSignedIn }
        return token
    }

    /// Public accessor that resolves (and caches) the account's home-region API
    /// base — used to sync the correct host to the watch.
    func resolvedRegionBase(auth: TeslaFleetAuth) async -> String {
        (try? await baseURL(auth: auth)) ?? TeslaFleetConfig.audience
    }

    /// Resolves the account's exact regional API base via `/api/1/users/region`
    /// and caches it. Tesla routes user data to the account's home-region host;
    /// calling the generic region URL can return 412. Falls back to the
    /// configured region host if the lookup fails.
    private func baseURL(auth: TeslaFleetAuth) async throws -> String {
        if let resolvedBaseURL { return resolvedBaseURL }
        let token = try await token(auth)
        var request = URLRequest(url: URL(string: TeslaFleetConfig.audience + "/api/1/users/region")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let region = try? JSONDecoder().decode(RegionResponse.self, from: data),
           let base = region.response.fleetApiBaseURL, !base.isEmpty {
            resolvedBaseURL = base
            return base
        }
        return TeslaFleetConfig.audience
    }

    private func get<T: Decodable>(_ path: String, auth: TeslaFleetAuth) async throws -> T {
        let token = try await token(auth)
        let base = try await baseURL(auth: auth)
        var request = URLRequest(url: URL(string: base + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func post(_ path: String, auth: TeslaFleetAuth, command: Bool) async throws -> Data {
        let token = try await token(auth)
        let base = command ? TeslaFleetConfig.commandBaseURL : (try await baseURL(auth: auth))
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            // Fleet API answers 408 for an offline/asleep vehicle.
            if http.statusCode == 408 {
                throw FleetError.asleep
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            let lowered = body.lowercased()
            if lowered.contains("command protocol") || lowered.contains("must be signed") || lowered.contains("unsigned") {
                throw FleetError.signingRequired
            }
            throw FleetError.http(http.statusCode, String(body.prefix(200)))
        }
    }

    // MARK: - Decodables

    private struct VehicleListResponse: Decodable {
        struct Vehicle: Decodable {
            let vin: String
            let display_name: String?
        }
        let response: [Vehicle]
    }

    private struct RegionResponse: Decodable {
        struct R: Decodable {
            let region: String?
            let fleetApiBaseURL: String?
            enum CodingKeys: String, CodingKey {
                case region
                case fleetApiBaseURL = "fleet_api_base_url"
            }
        }
        let response: R
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

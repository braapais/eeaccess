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
@MainActor
@Observable
final class TeslaFleetService {
    struct Snapshot: Sendable, Equatable {
        var batteryLevel: Int?
        var locked: Bool?
        var online: Bool?
        var insideTempC: Double?
    }

    private(set) var snapshot: Snapshot?
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

    func lock(vin: String, auth: TeslaFleetAuth) async {
        await command(vin: vin, action: "door_lock", label: "Locking…", auth: auth)
    }

    func unlock(vin: String, auth: TeslaFleetAuth) async {
        await command(vin: vin, action: "door_unlock", label: "Unlocking…", auth: auth)
    }

    func climateOn(vin: String, auth: TeslaFleetAuth) async {
        await command(vin: vin, action: "auto_conditioning_start", label: "Starting climate…", auth: auth)
    }

    func climateOff(vin: String, auth: TeslaFleetAuth) async {
        await command(vin: vin, action: "auto_conditioning_stop", label: "Stopping climate…", auth: auth)
    }

    private func command(vin: String, action: String, label: String, auth: TeslaFleetAuth) async {
        await run(label) {
            _ = try await self.post("/api/1/vehicles/\(vin)/command/\(action)", auth: auth, command: true)
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

    private func get<T: Decodable>(_ path: String, auth: TeslaFleetAuth) async throws -> T {
        let token = try await token(auth)
        var request = URLRequest(url: URL(string: TeslaFleetConfig.audience + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func post(_ path: String, auth: TeslaFleetAuth, command: Bool) async throws -> Data {
        let token = try await token(auth)
        let base = command ? TeslaFleetConfig.commandBaseURL : TeslaFleetConfig.audience
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

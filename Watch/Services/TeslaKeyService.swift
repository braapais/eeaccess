import CryptoKit
import Foundation
import Observation
import TeslaBLE

/// Watch-side wrapper around `TeslaVehicleClient` that drives BLE pairing and
/// daily lock / unlock / drive from SwiftUI.
///
/// The car is reached entirely over Bluetooth — no phone, no internet, no
/// Tesla account. The private key lives in the Keychain (device-only); this
/// service only holds it in memory for the duration of a connection.
@MainActor
@Observable
final class TeslaKeyService {
    /// Live BLE connection state, mirrored from the underlying client.
    private(set) var connection: ConnectionState = .disconnected
    /// True while a pairing or command operation is in flight.
    private(set) var isBusy = false
    /// Transient status line shown under the controls (e.g. "Unlocking…").
    private(set) var status: String?
    /// Last error message, if any.
    private(set) var lastError: String?

    /// Best-effort presence detector powering auto-unlock/lock. Observed by the
    /// UI for the proximity indicator.
    let presence = TeslaPresenceScanner()

    /// True while the open BLE link was made with `.pairing` mode. A pairing
    /// link has NO signed sessions even though the client reports `.connected`,
    /// so commands sent over it fail with "not connected" — and retrying can
    /// never fix it. Daily-use paths check this and reconnect normally first.
    private(set) var isPairingConnection = false

    private let keyStore: KeychainTeslaKeyStore
    private var client: TeslaVehicleClient?
    private var clientVIN: String?
    private var stateObservation: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?

    init(keychainService: String? = nil) {
        let service = keychainService
            ?? ((Bundle.main.bundleIdentifier ?? "com.elbaeverywhere.eeaccess") + ".teslakey")
        keyStore = KeychainTeslaKeyStore(service: service)
    }

    var isConnected: Bool { connection == .connected }

    /// Whether a private key already exists for this VIN (i.e. pairing has at
    /// least been started on this device).
    func hasKey(forVIN vin: String) -> Bool {
        (try? keyStore.loadPrivateKey(forVIN: vin)) != nil
    }

    // MARK: - Daily use

    @discardableResult
    func unlock(vin: String) async -> Bool {
        await perform(.security(.unlock), vin: vin, busy: "Unlocking…", done: "Unlocked")
    }

    @discardableResult
    func lock(vin: String) async -> Bool {
        await perform(.security(.lock), vin: vin, busy: "Locking…", done: "Locked")
    }

    /// Brings up the signed session so the car authorizes drive-away. Once
    /// connected with the watch present you can press the brake and drive —
    /// no separate command is needed, exactly like the phone key.
    @discardableResult
    func connect(vin: String) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; lastError = nil; status = "Connecting…"
        defer { isBusy = false }
        do {
            _ = try await usableClient(vin: vin)
            status = "Connected — ready to drive"
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func disconnect() async {
        status = nil
        isPairingConnection = false
        await client?.disconnect()
    }

    @discardableResult
    private func perform(_ command: Command, vin: String, busy: String, done: String) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; lastError = nil; status = busy
        defer { isBusy = false }
        do {
            let client = try await usableClient(vin: vin)
            try await client.send(command)
            setTransientStatus(done)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Returns a client with live signed sessions, tearing down a leftover
    /// pairing-mode link first (it reports `.connected` but cannot carry
    /// commands).
    private func usableClient(vin: String) async throws -> TeslaVehicleClient {
        let client = ensureClient(vin: vin)
        if isPairingConnection {
            await client.disconnect()
            isPairingConnection = false
        }
        if await client.state != .connected {
            try await client.connect()
        }
        return client
    }

    /// Shows `text` for a few seconds, then clears it — command results
    /// shouldn't read as current state forever.
    private func setTransientStatus(_ text: String) {
        status = text
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if self?.status == text { self?.status = nil }
        }
    }

    // MARK: - Auto entry (best-effort presence)

    /// Enables or disables presence-based auto-unlock (on approach) and
    /// auto-lock (on leave) for `vin`. Reliable while the Car screen is open;
    /// background is best-effort due to watchOS Bluetooth throttling.
    func setAutoEntry(_ enabled: Bool, vin: String) {
        guard enabled else { presence.stop(); return }
        presence.onEnterRange = { [weak self] in
            Task { await self?.autoTrigger(.security(.unlock), vin: vin, busy: "Approaching — unlocking…", done: "Unlocked") }
        }
        presence.onLeaveRange = { [weak self] in
            Task { await self?.autoTrigger(.security(.lock), vin: vin, busy: "Leaving — locking…", done: "Locked") }
        }
        presence.start(vin: vin)
    }

    private func autoTrigger(_ command: Command, vin: String, busy: String, done: String) async {
        // If a manual command is mid-flight, wait briefly instead of silently
        // dropping the approach/leave event (perform() no-ops while busy).
        var waited: Duration = .zero
        while isBusy, waited < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(500))
            waited += .milliseconds(500)
        }
        guard !isBusy else { return }
        presence.pause()
        await perform(command, vin: vin, busy: busy, done: done)
        presence.resume()
    }

    // MARK: - Pairing

    /// Step 1 of pairing: generate (or reuse) this watch's key and send the
    /// unsigned addKey request to the car over BLE. After this returns the
    /// user must tap an existing key card on the center console and confirm
    /// on the touchscreen, then call ``verifyPairing(vin:)``.
    ///
    /// - Returns: `true` if the request was transmitted; authorization still
    ///   completes asynchronously when the user taps their key card.
    func sendPairingRequest(vin: String, role: Command.KeyRole) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; lastError = nil; status = "Preparing key…"
        defer { isBusy = false }
        do {
            let privateKey: P256.KeyAgreement.PrivateKey
            if let existing = try keyStore.loadPrivateKey(forVIN: vin) {
                privateKey = existing
            } else {
                privateKey = KeyPairFactory.generateKeyPair()
                try keyStore.savePrivateKey(privateKey, forVIN: vin)
            }
            let publicKey = KeyPairFactory.publicKeyBytes(of: privateKey)

            let client = ensureClient(vin: vin)
            status = "Connecting to car…"
            try await client.connect(mode: .pairing)
            isPairingConnection = true
            status = "Sending key to car…"
            try await client.send(.security(.addKey(
                publicKey: publicKey,
                role: role,
                formFactor: .iosDevice
            )))
            // Keep the BLE connection OPEN while the user authorizes — Tesla's
            // reference flow holds the link during the key-card tap; dropping it
            // here can make the car discard the pending whitelist request, so
            // the key never enrolls and Verify fails with "missing signature
            // data". verifyPairing() tears this down before its normal-mode
            // handshake.
            status = "Now tap your Tesla key card on the center console and confirm on the car's screen — then tap Verify. Stay next to the car."
            return true
        } catch {
            // Don't leave a half-open pairing link behind on failure.
            if isPairingConnection {
                await client?.disconnect()
                isPairingConnection = false
            }
            fail(error)
            return false
        }
    }

    /// Step 2 of pairing: after the user authorized on the console, reconnect
    /// with a normal signed handshake. Success means the key is live.
    func verifyPairing(vin: String) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; lastError = nil; status = "Verifying…"
        defer { isBusy = false }
        do {
            let client = ensureClient(vin: vin)
            if await client.state != .disconnected { await client.disconnect() }
            isPairingConnection = false
            try await client.connect()
            status = "Paired ✓"
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Forget the key on this device. Does NOT remove it from the car — do
    /// that from the vehicle screen (Controls ▸ Locks ▸ Keys).
    func forgetKey(forVIN vin: String) {
        presence.stop()
        try? keyStore.deletePrivateKey(forVIN: vin)
        guard clientVIN == vin else { return }
        let dying = client
        stateObservation?.cancel()
        client = nil
        clientVIN = nil
        connection = .disconnected
        isPairingConnection = false
        Task { await dying?.disconnect() }
    }

    // MARK: - Internals

    private func ensureClient(vin: String) -> TeslaVehicleClient {
        if let client, clientVIN == vin { return client }
        stateObservation?.cancel()
        let newClient = TeslaVehicleClient(vin: vin, keyStore: keyStore)
        client = newClient
        clientVIN = vin
        connection = .disconnected
        isPairingConnection = false
        stateObservation = Task { [weak self] in
            for await state in newClient.stateStream {
                self?.connection = state
            }
        }
        return newClient
    }

    private func fail(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        status = nil
    }
}

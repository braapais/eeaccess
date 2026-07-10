import Foundation
import WatchConnectivity
import SwiftData

final class PhoneSyncService: NSObject, ObservableObject, WCSessionDelegate {
    struct WatchStatus: Sendable {
        let supported: Bool
        let activationState: String
        let isPaired: Bool
        let isWatchAppInstalled: Bool
        let isReachable: Bool
        let outstandingUserInfoTransfers: Int
        let bundleId: String

        var summary: String {
            """
            Supported: \(supported ? "yes" : "no")
            Activation: \(activationState)
            Paired: \(isPaired ? "yes" : "no")
            Watch app installed: \(isWatchAppInstalled ? "yes" : "no — known unreliable for independent apps")
            Reachable: \(isReachable ? "yes" : "no (watch app not in foreground)")
            Pending transfers: \(outstandingUserInfoTransfers)
            iOS bundle: \(bundleId)
            """
        }
    }

    @MainActor
    func currentStatus() -> WatchStatus {
        let stateName: String
        switch session.activationState {
        case .notActivated: stateName = "not activated"
        case .inactive: stateName = "inactive"
        case .activated: stateName = "activated"
        @unknown default: stateName = "unknown"
        }
        return WatchStatus(
            supported: WCSession.isSupported(),
            activationState: stateName,
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable,
            outstandingUserInfoTransfers: session.outstandingUserInfoTransfers.count,
            bundleId: Bundle.main.bundleIdentifier ?? "unknown"
        )
    }

    enum SyncResult: Sendable {
        case notSupported
        case notActivated
        case fetchFailed
        case noPairedWatch(Int)
        case sent(Int, reachable: Bool)

        var userMessage: String {
            switch self {
            case .notSupported:
                return "WatchConnectivity isn't supported on this device."
            case .notActivated:
                return "Connection isn't ready yet. Try again in a moment."
            case .fetchFailed:
                return "Couldn't read cards from local storage."
            case .noPairedWatch(let n):
                return "Queued \(n) card\(n == 1 ? "" : "s"). No Apple Watch is paired with this iPhone — pair one and the cards will sync."
            case .sent(let n, let reachable):
                if reachable {
                    return "Sent \(n) card\(n == 1 ? "" : "s") to your Apple Watch."
                } else {
                    return "Sent \(n) card\(n == 1 ? "" : "s") to the queue. They'll deliver the next time the EEAccess Watch app opens."
                }
            }
        }
    }

    private let session: WCSession = .default
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Upserts can include barcode/icon/card images that easily exceed
    /// `transferUserInfo`'s practical 64–256 KB ceiling, so we ship them via
    /// `transferFile` (no size limit, same queued-delivery semantics).
    func sendUpsert(card: Card) {
        guard session.activationState == .activated else { return }
        let payload = CardPayload(card: card)
        guard let data = payload.encode() else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eeaccess-card-\(card.id.uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        session.transferFile(url, metadata: ["action": "upsert", "id": card.id.uuidString])
    }

    /// Deletes also go via `transferFile` — `transferUserInfo` is unreliable
    /// in low-power / saturated-queue conditions. The file body is empty;
    /// the action and target id are carried in the metadata.
    func sendDelete(id: UUID) {
        guard session.activationState == .activated else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eeaccess-delete-\(id.uuidString).json")
        do {
            try Data().write(to: url, options: .atomic)
        } catch {
            return
        }
        session.transferFile(url, metadata: ["action": "delete", "id": id.uuidString])
    }

    /// Pushes the Tesla vehicle's identity (VIN, name, role) to the watch so
    /// the watch can pair as a BLE key without the user typing the VIN on the
    /// wrist. Only identity fields travel — the watch keeps its own BLE
    /// pairing status and private key locally.
    func sendTeslaVehicle(vin: String, displayName: String, keyRoleRaw: String, accessMode: String) {
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "vin": vin,
            "displayName": displayName,
            "keyRoleRaw": keyRoleRaw,
            "accessMode": accessMode,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eeaccess-tesla-\(vin).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        session.transferFile(url, metadata: ["action": "tesla-upsert"])
    }

    /// Syncs the current Fleet access token + region host to the watch so it
    /// can run cloud commands standalone. Uses application context (latest
    /// wins) rather than a queued transfer — the watch only needs the freshest
    /// token. The watch can't refresh, so the phone re-syncs whenever it's
    /// active.
    func sendTeslaCloudSession(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        baseURL: String,
        clientID: String,
        clientSecret: String
    ) {
        guard session.activationState == .activated else { return }
        // The refresh token + credentials let the watch refresh the access
        // token itself over LTE/WiFi (no phone). Device-only channel/storage.
        let context: [String: Any] = [
            "teslaAccessToken": accessToken,
            "teslaRefreshToken": refreshToken,
            "teslaExpiresAt": expiresAt.timeIntervalSince1970,
            "teslaBaseURL": baseURL,
            "teslaClientID": clientID,
            "teslaClientSecret": clientSecret,
        ]
        try? session.updateApplicationContext(context)
    }

    /// Syncs the relay's on/off flag + auto-provisioned API key to the watch so
    /// its cloud cars can go through the shared relay too. The relay's URL is a
    /// fixed constant on both platforms — nothing else to sync, no username or
    /// password ever exists to transfer. Sent as a file transfer (queued,
    /// delivered when the watch app next opens).
    func sendRelaySettings(enabled: Bool, apiKey: String) {
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = ["enabled": enabled, "apiKey": apiKey]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eeaccess-relay.json")
        do { try data.write(to: url, options: .atomic) } catch { return }
        session.transferFile(url, metadata: ["action": "relay-settings"])
    }

    /// Tells the watch to forget a Tesla vehicle's metadata. Does not remove
    /// the key from the watch Keychain or the car.
    func sendTeslaVehicleDelete(vin: String) {
        guard session.activationState == .activated else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eeaccess-tesla-delete-\(vin).json")
        do {
            try Data().write(to: url, options: .atomic)
        } catch {
            return
        }
        session.transferFile(url, metadata: ["action": "tesla-delete", "vin": vin])
    }

    /// Sends the watch the full list of currently-valid card ids. The watch
    /// uses this to prune any cards whose individual delete message was lost
    /// — self-healing reconciliation, runs after every full resync.
    private func sendManifest(ids: [UUID]) {
        guard session.activationState == .activated else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eeaccess-manifest-\(UUID().uuidString).json")
        let payload: [String: Any] = ["ids": ids.map(\.uuidString)]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        session.transferFile(url, metadata: ["action": "manifest"])
    }

    /// Push every card to the watch. Returns a SyncResult so the UI can give
    /// the user accurate feedback.
    @MainActor
    @discardableResult
    func resyncAll() -> SyncResult {
        guard WCSession.isSupported() else { return .notSupported }
        guard session.activationState == .activated else { return .notActivated }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Card>()
        guard let cards = try? context.fetch(descriptor) else { return .fetchFailed }

        for card in cards { sendUpsert(card: card) }
        sendManifest(ids: cards.map(\.id))

        if !session.isPaired {
            return .noPairedWatch(cards.count)
        }
        // Deliberately not checking isWatchAppInstalled — it's unreliable for
        // independent watch apps. The system queues regardless and delivers
        // when the watch app activates.
        return .sent(cards.count, reachable: session.isReachable)
    }

    // MARK: WCSessionDelegate

    /// On activation, force a full resync. Closes the gap where cards were
    /// added before the watch app was first launched (those `transferUserInfo`
    /// payloads can be queued/dropped depending on pairing timing).
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.resyncAll()
        }
    }

    /// Watch tells us a card was opened on it. Bump our local
    /// `lastUsedAt` to match so the iPhone list reflects the usage, and so
    /// the next resync doesn't overwrite the watch's bump with a stale value.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata
        Task { @MainActor in
            self.handleReceivedFile(metadata: metadata)
        }
    }

    @MainActor
    private func handleReceivedFile(metadata: [String: Any]?) {
        guard let action = metadata?["action"] as? String, action == "used" else {
            return
        }
        guard let idString = metadata?["id"] as? String,
              let id = UUID(uuidString: idString),
              let dateString = metadata?["at"] as? String,
              let date = ISO8601DateFormatter().date(from: dateString) else {
            return
        }
        let context = container.mainContext
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        guard let card = try? context.fetch(descriptor).first else { return }
        // Only forward in time — guards against out-of-order or duplicate
        // delivery accidentally regressing the timestamp.
        if date > card.lastUsedAt {
            card.lastUsedAt = date
            try? context.save()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

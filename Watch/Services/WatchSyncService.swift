import Foundation
import WatchConnectivity
import SwiftData

final class WatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    @Published var totalUserInfosReceived: Int = 0
    @Published var totalFilesReceived: Int = 0
    @Published var totalUpserts: Int = 0
    @Published var totalDeletes: Int = 0
    @Published var lastReceivedAt: Date?
    @Published var lastError: String?

    private let session: WCSession = .default
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.lastError = "Activation: \(error.localizedDescription)"
            }
        }
    }

    /// Tells the iPhone that this card was opened on the watch, so its
    /// `lastUsedAt` gets bumped on the phone too — keeps the "most recently
    /// used floats to top" rule consistent across devices instead of being
    /// reverted on the next phone resync.
    func sendCardUsed(id: UUID, at date: Date) {
        guard session.activationState == .activated else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eeaccess-used-\(id.uuidString).json")
        do {
            try Data().write(to: url, options: .atomic)
        } catch {
            return
        }
        let formatter = ISO8601DateFormatter()
        session.transferFile(url, metadata: [
            "action": "used",
            "id": id.uuidString,
            "at": formatter.string(from: date)
        ])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let info = userInfo
        Task { @MainActor in
            self.totalUserInfosReceived += 1
            self.lastReceivedAt = Date()
            self.handle(userInfo: info)
        }
    }

    /// File-based path used for upserts (carries the JSON-encoded CardPayload).
    /// The file URL is only valid for the duration of this delegate call, so
    /// we read the data synchronously, then dispatch the SwiftData work.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let data = try? Data(contentsOf: file.fileURL)
        let metadata = file.metadata
        Task { @MainActor in
            self.totalFilesReceived += 1
            self.lastReceivedAt = Date()
            self.handleReceivedFile(data: data, metadata: metadata)
        }
    }

    @MainActor
    private func handleReceivedFile(data: Data?, metadata: [String: Any]?) {
        guard let action = metadata?["action"] as? String else {
            lastError = "file: missing action"
            return
        }
        let context = container.mainContext

        switch action {
        case "upsert":
            guard let data else {
                lastError = "file upsert: read failed"
                return
            }
            guard let payload = CardPayload.decode(from: data) else {
                lastError = "file upsert: payload decode failed"
                return
            }
            do {
                try upsert(payload: payload, context: context)
                totalUpserts += 1
                lastError = nil
            } catch {
                lastError = "file upsert save: \(error.localizedDescription)"
            }
        case "delete":
            guard let idString = metadata?["id"] as? String,
                  let id = UUID(uuidString: idString) else {
                lastError = "file delete: invalid id"
                return
            }
            do {
                try delete(id: id, context: context)
                totalDeletes += 1
                lastError = nil
            } catch {
                lastError = "file delete save: \(error.localizedDescription)"
            }
        case "manifest":
            // Reconcile: any local card whose id is NOT in the manifest is
            // treated as deleted on the iPhone and removed locally too.
            guard let data else {
                lastError = "manifest: read failed"
                return
            }
            do {
                let object = try JSONSerialization.jsonObject(with: data)
                guard let dict = object as? [String: Any],
                      let idStrings = dict["ids"] as? [String] else {
                    lastError = "manifest: bad payload"
                    return
                }
                let validIds = Set(idStrings.compactMap(UUID.init(uuidString:)))
                try prune(notIn: validIds, context: context)
                lastError = nil
            } catch {
                lastError = "manifest: \(error.localizedDescription)"
            }
        case "tesla-upsert":
            guard let data else {
                lastError = "tesla upsert: read failed"
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any],
                  let vin = dict["vin"] as? String else {
                lastError = "tesla upsert: bad payload"
                return
            }
            let name = dict["displayName"] as? String ?? "Tesla"
            let role = dict["keyRoleRaw"] as? String ?? "driver"
            let accessMode = dict["accessMode"] as? String ?? TeslaAccessMode.bluetoothKey.rawValue
            do {
                try upsertTeslaVehicle(vin: vin, name: name, role: role, accessMode: accessMode, context: context)
                lastError = nil
            } catch {
                lastError = "tesla upsert save: \(error.localizedDescription)"
            }
        case "tesla-delete":
            guard let vin = metadata?["vin"] as? String else {
                lastError = "tesla delete: missing vin"
                return
            }
            do {
                try deleteTeslaVehicle(vin: vin, context: context)
                lastError = nil
            } catch {
                lastError = "tesla delete save: \(error.localizedDescription)"
            }
        default:
            lastError = "file: unsupported action \(action)"
        }
    }

    /// Upserts the Tesla vehicle metadata synced from the iPhone. Identity
    /// fields only — `isPaired` (the watch's BLE pairing status) is preserved.
    /// Once paired, `keyRoleRaw` is also preserved: the role is baked into the
    /// key enrolled on the car, so a phone-side change can't take effect
    /// without re-pairing — overwriting the label would just misreport it.
    private func upsertTeslaVehicle(vin: String, name: String, role: String, accessMode: String, context: ModelContext) throws {
        let mode = TeslaAccessMode(rawValue: accessMode) ?? .bluetoothKey
        let descriptor = FetchDescriptor<TeslaVehicle>(predicate: #Predicate { $0.vin == vin })
        if let existing = try context.fetch(descriptor).first {
            existing.displayName = name
            existing.accessMode = mode
            if !existing.isPaired {
                existing.keyRoleRaw = role
            }
        } else {
            context.insert(TeslaVehicle(vin: vin, displayName: name, isPaired: false, keyRoleRaw: role, accessMode: mode))
        }
        try context.save()
    }

    private func deleteTeslaVehicle(vin: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<TeslaVehicle>(predicate: #Predicate { $0.vin == vin })
        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }

    private func prune(notIn validIds: Set<UUID>, context: ModelContext) throws {
        let allCards = try context.fetch(FetchDescriptor<Card>())
        var removed = 0
        for card in allCards where !validIds.contains(card.id) {
            context.delete(card)
            removed += 1
        }
        if removed > 0 {
            try context.save()
            totalDeletes += removed
        }
    }

    @MainActor
    private func handle(userInfo: [String: Any]) {
        guard let action = userInfo["action"] as? String else {
            lastError = "userInfo missing action key"
            return
        }
        let context = container.mainContext

        switch action {
        case "upsert":
            guard let data = userInfo["card"] as? Data else {
                lastError = "upsert: missing card data"
                return
            }
            guard let payload = CardPayload.decode(from: data) else {
                lastError = "upsert: payload decode failed"
                return
            }
            do {
                try upsert(payload: payload, context: context)
                totalUpserts += 1
                lastError = nil
            } catch {
                lastError = "upsert save: \(error.localizedDescription)"
            }
        case "delete":
            guard let idString = userInfo["id"] as? String,
                  let id = UUID(uuidString: idString) else {
                lastError = "delete: invalid id"
                return
            }
            do {
                try delete(id: id, context: context)
                totalDeletes += 1
                lastError = nil
            } catch {
                lastError = "delete save: \(error.localizedDescription)"
            }
        default:
            lastError = "unknown action: \(action)"
        }
    }

    private func upsert(payload: CardPayload, context: ModelContext) throws {
        let id = payload.id
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.name = payload.name
            existing.barcodeValue = payload.barcodeValue
            existing.barcodeType = payload.barcodeType
            existing.barcodeImageData = payload.barcodeImageData
            existing.imageData = payload.imageData
            existing.iconImageData = payload.iconImageData
            existing.colorHex = payload.colorHex
            if let lastUsedAt = payload.lastUsedAt {
                existing.lastUsedAt = lastUsedAt
            }
        } else {
            let card = Card(
                id: payload.id,
                name: payload.name,
                barcodeValue: payload.barcodeValue,
                barcodeType: payload.barcodeType,
                barcodeImageData: payload.barcodeImageData,
                imageData: payload.imageData,
                iconImageData: payload.iconImageData,
                colorHex: payload.colorHex,
                createdAt: payload.createdAt,
                lastUsedAt: payload.lastUsedAt
            )
            context.insert(card)
        }
        try context.save()
    }

    private func delete(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }
}

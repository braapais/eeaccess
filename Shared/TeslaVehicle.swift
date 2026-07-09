import Foundation
import SwiftData

/// How the app reaches a given Tesla.
enum TeslaAccessMode: String, CaseIterable, Sendable {
    /// Bluetooth phone-key on the watch (Model 3/Y, Cybertruck, 2021+ S/X).
    /// No account or internet needed.
    case bluetoothKey = "ble"
    /// Tesla Fleet API over the internet, using your Tesla account (OAuth).
    /// The only path for pre-2021 Model S/X, which have no BLE phone key.
    /// Pre-2021 cars accept unsigned commands, so no signing proxy is needed.
    case cloud = "cloud"

    var title: String {
        switch self {
        case .bluetoothKey: "Apple Watch key"
        case .cloud: "Cloud (Tesla account)"
        }
    }
}

/// A Tesla the watch has been (or is being) set up to unlock as a BLE key.
///
/// Only metadata lives here. The actual P-256 private key is stored in the
/// Keychain by `KeychainTeslaKeyStore`, keyed by VIN, device-only and never
/// synced to iCloud or backups. Deleting this record does **not** remove the
/// key from the car — that must be done from the vehicle's touchscreen
/// (Controls ▸ Locks ▸ Keys).
@Model
final class TeslaVehicle {
    /// 17-character VIN. The car advertises a BLE local name derived from
    /// this, so it is also how the BLE client finds the right vehicle.
    @Attribute(.unique) var vin: String
    /// User-facing name shown on the watch (e.g. "Model X").
    var displayName: String
    /// True once the key has been added to the car and a normal (signed)
    /// session has handshaked successfully at least once.
    var isPaired: Bool
    /// Role the key was enrolled with: "driver" or "owner".
    var keyRoleRaw: String
    /// How the app reaches this car — `TeslaAccessMode` raw value. Defaulted so
    /// existing records migrate to the Bluetooth key without a schema break.
    var accessModeRaw: String = TeslaAccessMode.bluetoothKey.rawValue
    /// Watch-local: whether best-effort presence auto-unlock/lock is enabled.
    /// Not overwritten by iPhone sync.
    var autoEntryEnabled: Bool
    var createdAt: Date
    var lastConnectedAt: Date?

    /// Typed accessor over ``accessModeRaw`` (transient — not itself persisted).
    var accessMode: TeslaAccessMode {
        get { TeslaAccessMode(rawValue: accessModeRaw) ?? .bluetoothKey }
        set { accessModeRaw = newValue.rawValue }
    }

    init(
        vin: String,
        displayName: String,
        isPaired: Bool = false,
        keyRoleRaw: String = "driver",
        accessMode: TeslaAccessMode = .bluetoothKey,
        autoEntryEnabled: Bool = false,
        createdAt: Date = .now,
        lastConnectedAt: Date? = nil
    ) {
        self.vin = vin
        self.displayName = displayName
        self.isPaired = isPaired
        self.keyRoleRaw = keyRoleRaw
        self.accessModeRaw = accessMode.rawValue
        self.autoEntryEnabled = autoEntryEnabled
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
    }
}

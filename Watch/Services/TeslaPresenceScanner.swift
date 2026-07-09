import CoreBluetooth
import CryptoKit
import Foundation
import Observation

/// Best-effort BLE presence detector for the paired Tesla.
///
/// Scans for the vehicle's VIN-derived advertisement local name and reports
/// near / far transitions so the app can auto-unlock on approach and auto-lock
/// on leave. Detection is reliable while the watch app is **active**; watchOS
/// throttles Bluetooth in the background, so background auto-entry is
/// best-effort and must not be relied on as your only key.
@MainActor
@Observable
final class TeslaPresenceScanner: NSObject {
    enum Proximity: Sendable { case unknown, near, far }

    private(set) var proximity: Proximity = .unknown
    private(set) var isMonitoring = false
    private(set) var lastRSSI: Int?

    /// Fired on a far/unknown → near transition (you walked up).
    var onEnterRange: (() -> Void)?
    /// Fired on a sustained near → far transition (you walked away).
    var onLeaveRange: (() -> Void)?
    /// Returns true while a live BLE command link to the car is open. The car
    /// stops advertising while connected, so the scan goes silent exactly when
    /// we are provably next to it — without this, the loss timer fires a
    /// phantom "walked away" (and auto-lock) right after an auto-unlock.
    var hasLiveConnection: (() -> Bool)?

    /// RSSI at or above which the car counts as "near" (a few metres).
    var nearThresholdDBM = -70
    /// Treat the car as gone if not seen for this long.
    var lossInterval: TimeInterval = 30

    private var central: CBCentralManager?
    private var targetLocalName: String?
    private var lastSeen: Date?
    private var lossTimer: Timer?
    private var paused = false
    private var appActive = true

    func start(vin: String) {
        targetLocalName = Self.bleLocalName(for: vin)
        isMonitoring = true
        paused = false
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginScan()
        }
        startLossTimer()
    }

    func stop() {
        isMonitoring = false
        central?.stopScan()
        lossTimer?.invalidate()
        lossTimer = nil
        proximity = .unknown
        lastRSSI = nil
        lastSeen = nil
    }

    /// Pause scanning while a command connection owns the radio.
    func pause() {
        paused = true
        central?.stopScan()
    }

    func resume() {
        paused = false
        beginScan()
    }

    /// Tells the scanner whether the app is frontmost. A nil-service scan
    /// simply stops running when a watch app backgrounds, so "no sighting for
    /// 30s" in background means throttling, not distance — acting on it sends
    /// a spurious lock, then a phantom unlock on the next foreground. While
    /// inactive, both transitions are suppressed; on reactivation, presence is
    /// re-detected from scratch.
    func setAppActive(_ active: Bool) {
        appActive = active
        guard isMonitoring else { return }
        if active {
            proximity = .unknown
            lastSeen = nil
            lastRSSI = nil
            beginScan()
        }
    }

    private func beginScan() {
        guard isMonitoring, !paused, let central, central.state == .poweredOn else { return }
        // Match the library's discovery: scan without a service filter and
        // identify the vehicle by its advertised local name. Reliable while the
        // app is active; background scanning is throttled by watchOS. (If the
        // car turns out to advertise its service UUID, switching to a filtered
        // scan here would improve background behaviour.)
        //
        // Duplicates MUST be allowed: with filtering on, CoreBluetooth
        // coalesces a peripheral's adverts into a single discovery per scan
        // session, so the car is reported once (often still far away, below
        // the near threshold) and the RSSI never updates as the user walks
        // up — auto-unlock then only ever fires on lucky timing. Continuous
        // delivery is foreground-only, which matches this scanner's app-active
        // gating anyway.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func startLossTimer() {
        lossTimer?.invalidate()
        lossTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForLoss() }
        }
    }

    private func checkForLoss() {
        // While paused the scan isn't running, so "no sightings" means
        // nothing; while connected the car doesn't advertise at all — keep
        // the sighting fresh so disconnect starts a clean 30 s window.
        guard appActive, !paused, proximity == .near else { return }
        if hasLiveConnection?() == true {
            lastSeen = Date()
            return
        }
        guard let lastSeen else { return }
        if Date().timeIntervalSince(lastSeen) > lossInterval {
            proximity = .far
            onLeaveRange?()
        }
    }

    /// Mirrors TeslaBLE's (internal) VINHelper: "S" + first 8 bytes of
    /// SHA1(VIN) as lowercase hex + "C".
    private static func bleLocalName(for vin: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(vin.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "S\(hex)C"
    }
}

// `CBCentralManagerDelegate` is not `@MainActor`-isolated, but we initialize
// the manager with `queue: .main`, so callbacks really do run on the main
// queue. Mark the conformance `nonisolated` and use `MainActor.assumeIsolated`
// to bridge into the actor-isolated state — this keeps Swift 6's strict
// concurrency checker happy without changing runtime behavior.
extension TeslaPresenceScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn { beginScan() }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            guard name == targetLocalName else { return }
            lastSeen = Date()
            lastRSSI = RSSI.intValue
            // Auto-unlock is security-sensitive: only fire it while the app is
            // frontmost, so unlocking is always tied to user intent (screen
            // awake near the car), never to a stale background sighting.
            guard appActive else { return }
            if RSSI.intValue >= nearThresholdDBM, proximity != .near {
                proximity = .near
                onEnterRange?()
            }
        }
    }
}

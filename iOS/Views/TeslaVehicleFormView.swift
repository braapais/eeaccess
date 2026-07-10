import SwiftUI
import SwiftData

/// Add or edit a single Tesla (VIN, name, role) and sync it to the watch.
/// Pass `nil` to create a new vehicle.
struct TeslaVehicleFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: PhoneSyncService
    @Environment(TeslaFleetService.self) private var fleet
    @Environment(TeslaFleetAuth.self) private var fleetAuth
    @Environment(RelayServerClient.self) private var relay
    @Query(sort: \TeslaVehicle.createdAt) private var vehicles: [TeslaVehicle]

    let vehicle: TeslaVehicle?

    @State private var vin = ""
    @State private var name = ""
    @State private var role = "driver"
    @State private var accessMode: TeslaAccessMode = .bluetoothKey
    @State private var savedNote: String?

    // VINs never contain I, O, or Q — strip them along with separators.
    private var cleanVIN: String {
        vin.uppercased().filter { ($0.isLetter || $0.isNumber) && !"IOQ".contains($0) }
    }

    /// The VIN is the record's identity on both devices (unique attribute
    /// here, sync key on the watch) — a second record can't share it.
    private var vinTakenByOther: Bool {
        vehicles.contains { $0.vin == cleanVIN && $0.persistentModelID != vehicle?.persistentModelID }
    }

    var body: some View {
        Form {
            if vehicle == nil, fleetAuth.isSignedIn || relay.isActive {
                accountVehiclesSection
            }
            Section("Vehicle") {
                TextField("VIN (17 characters)", text: $vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Name", text: $name)
                if vehicle != nil, fleetAuth.isSignedIn || relay.isActive {
                    Button {
                        Task { await importNameFromTesla() }
                    } label: {
                        if importingName {
                            HStack { ProgressView(); Text("Looking up…") }
                        } else {
                            Label("Get name from Tesla", systemImage: "arrow.down.doc")
                        }
                    }
                    .font(.footnote)
                    .disabled(cleanVIN.count != 17 || importingName)
                }
                Picker("Access", selection: $accessMode) {
                    ForEach(TeslaAccessMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if accessMode == .bluetoothKey {
                    Picker("Key role", selection: $role) {
                        Text("Driver").tag("driver")
                        Text("Owner").tag("owner")
                    }
                    .pickerStyle(.segmented)
                }
                Button {
                    save()
                } label: {
                    Label(
                        vehicle == nil ? "Save & sync to watch" : "Update & sync to watch",
                        systemImage: "applewatch.radiowaves.left.and.right"
                    )
                }
                .disabled(cleanVIN.count != 17 || vinTakenByOther)
                if vinTakenByOther {
                    Text("Another vehicle already uses this VIN.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let savedNote {
                    Text(savedNote).font(.footnote).foregroundStyle(.green)
                }
                Text(accessMode == .cloud
                     ? "Cloud car (pre-2021 Model S/X): controlled from iPhone over the internet using your Tesla account — connect it below. No in-car pairing, and it won't appear as a Bluetooth key on the watch."
                     : "Bluetooth key: pair on your Apple Watch in the car with your Tesla key card. Works with no account and no internet. For Model 3/Y, Cybertruck, and 2021 or newer Model S/X.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // The relay server only sends unsigned commands, so it's only a
            // usable backend for .cloud (pre-2021) cars — see cloudControl.
            if let vehicle, fleetAuth.isSignedIn || (relay.isActive && vehicle.accessMode == .cloud) {
                cloudControl(vehicle)
            }
            if vehicle != nil {
                Section {
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Label("Remove vehicle", systemImage: "trash")
                    }
                    Text("Removes it from this iPhone and the watch. The watch's key stays in its Keychain, and the key stays enrolled on the car — remove that from the car's screen (Controls ▸ Locks ▸ Keys).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(vehicle == nil ? "Add Vehicle" : "Edit Vehicle")
        .onAppear {
            if let vehicle {
                vin = vehicle.vin
                name = vehicle.displayName
                role = vehicle.keyRoleRaw
                accessMode = vehicle.accessMode
            } else {
                if name.isEmpty { name = "Tesla" }
                // Pull the account's cars so the user can pick instead of typing —
                // prefer the relay (works with no separate BYOC connection) but
                // fall back to the direct Tesla account if that's what's signed in.
                if relay.isActive, relay.accountVehicles.isEmpty {
                    Task { await relay.fetchVehicles() }
                } else if fleetAuth.isSignedIn, fleet.accountVehicles.isEmpty {
                    Task { await fleet.fetchVehicles(auth: fleetAuth) }
                }
            }
        }
    }

    // MARK: - Import from account

    /// Common shape over the two possible sources (relay vs. direct BYOC) so
    /// the import UI doesn't need to care which one is active.
    private struct AccountVehicle: Identifiable {
        let vin: String
        let displayName: String
        var id: String { vin }
    }

    private var accountVehicles: [AccountVehicle] {
        if relay.isActive {
            return relay.accountVehicles.map { AccountVehicle(vin: $0.vin, displayName: $0.displayName) }
        }
        return fleet.accountVehicles.map { AccountVehicle(vin: $0.vin, displayName: $0.displayName) }
    }
    private var accountIsBusy: Bool { relay.isActive ? relay.isBusy : fleet.isBusy }
    private var accountError: String? { relay.isActive ? relay.lastError : fleet.lastError }
    private func refreshAccountVehicles() async {
        if relay.isActive { await relay.fetchVehicles() } else { await fleet.fetchVehicles(auth: fleetAuth) }
    }

    @ViewBuilder
    private var accountVehiclesSection: some View {
        Section("From your Tesla account") {
            if accountVehicles.isEmpty {
                if accountIsBusy {
                    HStack { ProgressView(); Text("Loading your vehicles…") }
                } else if let error = accountError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Text("No vehicles found on your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(accountVehicles) { fv in
                    Button {
                        vin = fv.vin
                        name = fv.displayName
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fv.displayName)
                                    .foregroundStyle(.primary)
                                Text(fv.vin)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if cleanVIN == fv.vin {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            if !relay.isActive, let base = fleet.resolvedBaseURL {
                Text("Region host: \(base.replacingOccurrences(of: "https://", with: ""))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await refreshAccountVehicles() }
            } label: {
                Label("Refresh list", systemImage: "arrow.clockwise")
            }
            .font(.footnote)
        }
    }

    /// Looks up this VIN on whichever Tesla connection is active and, if
    /// found, fills the Name field with Tesla's own display name for it.
    @State private var importingName = false
    private func importNameFromTesla() async {
        importingName = true
        defer { importingName = false }
        await refreshAccountVehicles()
        if let match = accountVehicles.first(where: { $0.vin == cleanVIN }) {
            name = match.displayName
        }
    }

    // MARK: - Cloud control (per car)

    @ViewBuilder
    private func cloudControl(_ vehicle: TeslaVehicle) -> some View {
        let vin = vehicle.vin
        // Pre-2021 S/X accept unsigned commands (no proxy); 2021+ need signing.
        let unsigned = vehicle.accessMode == .cloud
        // The relay server only ever sends unsigned commands — never route a
        // signed (2021+) car through it, or a scheduled Unlock+Drive would
        // fail silently at fire time instead of visibly like a direct tap does.
        let useRelay = relay.isActive && unsigned
        Section(useRelay ? "Cloud control (via server)" : "Cloud control") {
            if useRelay, let s = relay.snapshot {
                snapshotRows(battery: s.batteryLevel, locked: s.locked, online: s.online, inside: s.insideTempC)
            } else if !useRelay, let s = fleet.snapshot {
                snapshotRows(battery: s.batteryLevel, locked: s.locked, online: s.online, inside: s.insideTempC)
            }

            Button {
                Task { useRelay ? await relay.refreshState(vin: vin) : await fleet.refresh(vin: vin, auth: fleetAuth) }
            } label: { Label("Refresh state", systemImage: "arrow.clockwise") }
            Button {
                Task { useRelay ? await relay.wake(vin: vin) : await fleet.wake(vin: vin, auth: fleetAuth) }
            } label: { Label("Wake", systemImage: "sun.max") }

            HStack {
                Button {
                    Task { useRelay ? await relay.unlock(vin: vin) : await fleet.unlock(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: { Label("Unlock", systemImage: "lock.open").frame(maxWidth: .infinity) }
                Button {
                    Task { useRelay ? await relay.lock(vin: vin) : await fleet.lock(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: { Label("Lock", systemImage: "lock").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)

            Button {
                Task { useRelay ? await relay.drive(vin: vin) : await fleet.startDrive(vin: vin, auth: fleetAuth, unsigned: unsigned) }
            } label: { Label("Start Drive", systemImage: "steeringwheel").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
            .tint(.blue)

            Button {
                Task {
                    if useRelay {
                        await relay.unlockAndDrive(vin: vin)
                    } else {
                        await fleet.unlockAndDrive(vin: vin, auth: fleetAuth, unsigned: unsigned)
                    }
                }
            } label: { Label("Unlock & Drive", systemImage: "bolt.car").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            scheduleControls(vin: vin, unsigned: unsigned, useRelay: useRelay)

            HStack {
                Button {
                    Task { useRelay ? await relay.climateOn(vin: vin) : await fleet.climateOn(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: { Label("Climate On", systemImage: "fan").frame(maxWidth: .infinity) }
                Button {
                    Task { useRelay ? await relay.climateOff(vin: vin) : await fleet.climateOff(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: { Label("Off", systemImage: "fan.slash").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)

            if let status = useRelay ? relay.status : fleet.status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = useRelay ? relay.lastError : fleet.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .disabled(useRelay ? relay.isBusy : fleet.isBusy)
        .onAppear { if useRelay { Task { await relay.refreshSchedules() } } }
    }

    @ViewBuilder
    private func scheduleControls(vin: String, unsigned: Bool, useRelay: Bool) -> some View {
        if useRelay {
            if relay.pendingSchedule(for: vin) != nil {
                Button(role: .destructive) {
                    Task { await relay.cancelSchedule(vin: vin) }
                } label: {
                    Label("Cancel scheduled Unlock & Drive", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await relay.scheduleUnlockDrive(vin: vin, delay: 60) }
                } label: {
                    Label("Unlock & Drive in 60s (server)", systemImage: "timer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            Text("Runs on your server — fires even if this phone loses signal in the garage.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            if let secs = fleet.scheduledSeconds {
                Button(role: .destructive) {
                    fleet.cancelSchedule()
                } label: {
                    Label("Cancel — Unlock & Drive in \(secs)s", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    fleet.scheduleUnlockDrive(vin: vin, auth: fleetAuth, unsigned: unsigned, delay: 60)
                } label: {
                    Label("Unlock & Drive in 60s", systemImage: "timer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            Text("Tap while you still have signal, then walk to the car. Keep this screen open (fires on this device).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func snapshotRows(battery: Int?, locked: Bool?, online: Bool?, inside: Double?) -> some View {
        Group {
            if let battery { LabeledContent("Battery", value: "\(battery)%") }
            if let locked { LabeledContent("Locked", value: locked ? "Yes" : "No") }
            if let online { LabeledContent("State", value: online ? "Online" : "Asleep") }
            if let inside { LabeledContent("Inside", value: "\(Int(inside))°C") }
        }
    }

    private func save() {
        // The VIN keys the watch-side record; if it changed, retire the old
        // one there or the watch would keep a stale duplicate.
        if let vehicle, vehicle.vin != cleanVIN {
            sync.sendTeslaVehicleDelete(vin: vehicle.vin)
        }
        let target = vehicle ?? TeslaVehicle(vin: cleanVIN, displayName: name)
        target.vin = cleanVIN
        target.displayName = name.isEmpty ? "Tesla" : name
        target.keyRoleRaw = role
        target.accessMode = accessMode
        if vehicle == nil { context.insert(target) }
        try? context.save()
        sync.sendTeslaVehicle(
            vin: target.vin,
            displayName: target.displayName,
            keyRoleRaw: target.keyRoleRaw,
            accessMode: target.accessModeRaw
        )
        savedNote = accessMode == .cloud
            ? "Saved & synced. Connect your Tesla account below to control it."
            : "Saved & synced to your Apple Watch"
    }

    private func remove() {
        guard let vehicle else { return }
        sync.sendTeslaVehicleDelete(vin: vehicle.vin)
        context.delete(vehicle)
        try? context.save()
        dismiss()
    }
}

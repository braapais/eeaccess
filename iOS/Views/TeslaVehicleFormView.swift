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
            Section("Vehicle") {
                TextField("VIN (17 characters)", text: $vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Name", text: $name)
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
            if let vehicle, fleetAuth.isSignedIn {
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
            } else if name.isEmpty {
                name = "Tesla"
            }
        }
    }

    // MARK: - Cloud control (per car)

    @ViewBuilder
    private func cloudControl(_ vehicle: TeslaVehicle) -> some View {
        Section("Cloud control") {
            let vin = vehicle.vin
            // Pre-2021 S/X accept unsigned commands (no proxy); 2021+ need the
            // signing proxy at commandBaseURL.
            let unsigned = vehicle.accessMode == .cloud
            if let snap = fleet.snapshot {
                snapshotRows(snap)
            }
            Button {
                Task { await fleet.refresh(vin: vin, auth: fleetAuth) }
            } label: {
                Label("Refresh state", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await fleet.wake(vin: vin, auth: fleetAuth) }
            } label: {
                Label("Wake", systemImage: "sun.max")
            }
            HStack {
                Button {
                    Task { await fleet.unlock(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: {
                    Label("Unlock", systemImage: "lock.open").frame(maxWidth: .infinity)
                }
                Button {
                    Task { await fleet.lock(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: {
                    Label("Lock", systemImage: "lock").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            HStack {
                Button {
                    Task { await fleet.climateOn(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: {
                    Label("Climate On", systemImage: "fan").frame(maxWidth: .infinity)
                }
                Button {
                    Task { await fleet.climateOff(vin: vin, auth: fleetAuth, unsigned: unsigned) }
                } label: {
                    Label("Off", systemImage: "fan.slash").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            if let status = fleet.status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = fleet.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .disabled(fleet.isBusy)
    }

    private func snapshotRows(_ snap: TeslaFleetService.Snapshot) -> some View {
        Group {
            if let b = snap.batteryLevel { LabeledContent("Battery", value: "\(b)%") }
            if let l = snap.locked { LabeledContent("Locked", value: l ? "Yes" : "No") }
            if let o = snap.online { LabeledContent("State", value: o ? "Online" : "Asleep") }
            if let t = snap.insideTempC { LabeledContent("Inside", value: "\(Int(t))°C") }
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

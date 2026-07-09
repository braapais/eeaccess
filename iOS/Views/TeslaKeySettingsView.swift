import SwiftUI
import SwiftData

/// iPhone setup + cloud control for the Tesla keys: manage your vehicles
/// (VIN/name/role, synced to the watch so you don't type on the wrist),
/// connect your Tesla account, and send cloud commands. In-car BLE pairing
/// happens on the watch — once per vehicle.
struct TeslaKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TeslaFleetAuth.self) private var fleetAuth
    @Environment(TeslaFleetService.self) private var fleet
    @Query(sort: \TeslaVehicle.createdAt) private var vehicles: [TeslaVehicle]

    /// VIN of the vehicle targeted by the cloud-control section.
    @State private var cloudVIN = ""

    private var cloudVehicle: TeslaVehicle? {
        vehicles.first(where: { $0.vin == cloudVIN }) ?? vehicles.first
    }

    var body: some View {
        Form {
            vehicleSection
            accountSection
            cloudSection
            Section {
                Text("Pairing the watch as a Bluetooth key happens in the car: open EEAccess on your Apple Watch → Tesla Key → Set Up Key, with that car's Tesla key card. Repeat once per vehicle. The Bluetooth key works with no account and no internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tesla Key")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            if cloudVehicle?.vin != cloudVIN {
                cloudVIN = vehicles.first?.vin ?? ""
            }
        }
    }

    // MARK: - Vehicles

    private var vehicleSection: some View {
        Section("Vehicles") {
            ForEach(vehicles) { vehicle in
                NavigationLink {
                    TeslaVehicleFormView(vehicle: vehicle)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(vehicle.displayName)
                            Spacer()
                            Label(vehicle.accessMode == .cloud ? "Cloud" : "Watch key",
                                  systemImage: vehicle.accessMode == .cloud ? "cloud" : "applewatch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }
                        Text(vehicle.vin)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink {
                TeslaVehicleFormView(vehicle: nil)
            } label: {
                Label("Add Vehicle", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section("Tesla account (cloud control)") {
            switch fleetAuth.status {
            case .notConfigured:
                Label("Not configured", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Add your developer.tesla.com Client ID in TeslaFleetConfig to enable cloud commands. The watch's Bluetooth key works without this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .signedOut, .failed:
                Button {
                    Task { await fleetAuth.connect() }
                } label: {
                    Label("Connect Tesla Account", systemImage: "person.badge.key")
                }
                if case let .failed(message) = fleetAuth.status {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            case .connecting:
                HStack { ProgressView(); Text("Connecting…") }
            case .signedIn:
                Label("Connected", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button(role: .destructive) {
                    fleetAuth.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "person.badge.minus")
                }
            }
        }
    }

    // MARK: - Cloud control

    @ViewBuilder
    private var cloudSection: some View {
        if fleetAuth.isSignedIn {
            Section("Cloud control") {
                if vehicles.count > 1 {
                    Picker("Vehicle", selection: $cloudVIN) {
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.displayName).tag(vehicle.vin)
                        }
                    }
                }
                if let vin = cloudVehicle?.vin {
                    // Pre-2021 S/X accept unsigned commands (no proxy); 2021+
                    // need the signing proxy at commandBaseURL.
                    let unsigned = cloudVehicle?.accessMode == .cloud
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
                } else {
                    Text("Save your VIN above to use cloud control.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(fleet.isBusy)
        }
    }

    private func snapshotRows(_ snap: TeslaFleetService.Snapshot) -> some View {
        Group {
            if let b = snap.batteryLevel { LabeledContent("Battery", value: "\(b)%") }
            if let l = snap.locked { LabeledContent("Locked", value: l ? "Yes" : "No") }
            if let o = snap.online { LabeledContent("State", value: o ? "Online" : "Asleep") }
            if let t = snap.insideTempC { LabeledContent("Inside", value: "\(Int(t))°C") }
        }
    }
}

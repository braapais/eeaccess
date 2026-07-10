import SwiftUI
import SwiftData

/// iPhone setup for the Tesla keys: manage your vehicles (VIN/name/mode, synced
/// to the watch) and connect your Tesla account. Per-car cloud commands live in
/// `TeslaVehicleFormView`; in-car BLE pairing happens on the watch.
struct TeslaKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TeslaFleetAuth.self) private var fleetAuth
    @Query(sort: \TeslaVehicle.createdAt) private var vehicles: [TeslaVehicle]

    var body: some View {
        Form {
            vehicleSection
            accountSection
            Section("Relay (optional)") {
                NavigationLink {
                    RelayServerView()
                } label: {
                    Label("Relay", systemImage: "server.rack")
                }
                Text("Route cloud commands through EEAccess's relay so a scheduled Unlock+Drive fires even when your phone/watch has no signal. Just sign in — no server to set up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                Text("Cloud control needs your own Tesla developer credentials (bring-your-own). Tap below to enter them. The watch's Bluetooth key works without this.")
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
            NavigationLink {
                TeslaCredentialsView()
            } label: {
                Label("Tesla API credentials", systemImage: "key.horizontal")
                    .font(.footnote)
            }
        }
        if fleetAuth.isSignedIn {
            Section {
                Text("Cloud commands (Refresh, Wake, Lock/Unlock, Climate) are on each car's screen — tap a vehicle above.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

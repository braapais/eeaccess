import SwiftUI
import SwiftData
import TeslaBLE

/// Main Tesla Key screen on the watch: lock / unlock / connect-to-drive, or a
/// prompt to set the car up if no key has been paired yet.
struct WatchTeslaKeyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TeslaKeyService.self) private var key
    @Query(sort: \TeslaVehicle.createdAt) private var vehicles: [TeslaVehicle]

    var body: some View {
        Group {
            if let vehicle = vehicles.first {
                if vehicle.isPaired {
                    controls(for: vehicle)
                } else {
                    finishSetupPrompt(vehicle)
                }
            } else {
                setupPrompt
            }
        }
        .navigationTitle("Tesla Key")
        .onChange(of: scenePhase) { _, phase in
            key.presence.setAppActive(phase == .active)
        }
    }

    private func finishSetupPrompt(_ vehicle: TeslaVehicle) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(vehicle.displayName)
                .font(.headline)
            Text("Finish pairing in your car to use this watch as a key.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink("Finish Pairing", destination: WatchPairingView())
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Set up your Tesla as a key")
                .font(.footnote)
                .multilineTextAlignment(.center)
            NavigationLink("Set Up Key", destination: WatchPairingView())
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @ViewBuilder
    private func controls(for vehicle: TeslaVehicle) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                header(vehicle)

                Button {
                    Task { if await key.unlock(vin: vehicle.vin) { bump(vehicle) } }
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    Task { if await key.lock(vin: vehicle.vin) { bump(vehicle) } }
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { if await key.startDrive(vin: vehicle.vin) { bump(vehicle) } }
                } label: {
                    Label("Start Drive", systemImage: "steeringwheel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                if key.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Divider()

                Toggle(isOn: autoEntryBinding(vehicle)) {
                    Label("Auto-unlock near car", systemImage: "sensor.tag.radiowaves.forward")
                }
                .font(.caption)

                if vehicle.autoEntryEnabled {
                    Label(proximityText, systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Acts only while the app is awake on screen — watchOS pauses Bluetooth scanning in the background.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let status = key.status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let err = key.lastError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                NavigationLink("Manage Key", destination: WatchPairingView())
                    .font(.caption2)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .disabled(key.isBusy)
            .overlay {
                if key.isBusy { ProgressView() }
            }
        }
        .onAppear {
            if vehicle.autoEntryEnabled {
                key.setAutoEntry(true, vin: vehicle.vin)
            }
        }
    }

    private func autoEntryBinding(_ vehicle: TeslaVehicle) -> Binding<Bool> {
        Binding(
            get: { vehicle.autoEntryEnabled },
            set: { newValue in
                vehicle.autoEntryEnabled = newValue
                try? context.save()
                key.setAutoEntry(newValue, vin: vehicle.vin)
            }
        )
    }

    private var proximityText: String {
        switch key.presence.proximity {
        case .near: "Car detected nearby"
        case .far: "Out of range"
        case .unknown: "Searching…"
        }
    }

    private func header(_ vehicle: TeslaVehicle) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(vehicle.displayName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
        }
    }

    private var dotColor: Color {
        switch key.connection {
        case .connected: .green
        case .scanning, .connecting, .handshaking: .orange
        case .disconnected: .gray
        }
    }

    private func bump(_ vehicle: TeslaVehicle) {
        vehicle.lastConnectedAt = .now
        try? context.save()
    }
}

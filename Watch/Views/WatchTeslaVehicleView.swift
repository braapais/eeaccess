import SwiftUI
import SwiftData
import TeslaBLE

/// Controls for a single paired Tesla on the watch: lock / unlock / start
/// drive / auto-unlock. Shows a finish-pairing prompt if the car was set up
/// on the phone but not yet paired in the car.
struct WatchTeslaVehicleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TeslaKeyService.self) private var key
    @Environment(WatchTeslaCloud.self) private var cloud
    @Environment(RelayServerClient.self) private var relay

    let vehicle: TeslaVehicle

    var body: some View {
        Group {
            if vehicle.accessMode == .cloud {
                cloudControls
            } else if vehicle.isPaired {
                controls
            } else {
                finishSetupPrompt
            }
        }
        .navigationTitle(vehicle.displayName)
        .onChange(of: scenePhase) { _, phase in
            key.presence.setAppActive(phase == .active)
        }
    }

    /// Cloud cars: via the relay server if configured, else directly over the
    /// synced Fleet session.
    @ViewBuilder
    private var cloudControls: some View {
        if relay.isActive {
            relayControls
        } else {
            directCloudControls
        }
    }

    /// Route commands through the self-hosted relay server (Basic auth). Its
    /// scheduled Unlock+Drive runs server-side, so it fires even if the watch
    /// is offline in the garage.
    @ViewBuilder
    private var relayControls: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    Task { await relay.unlock(vin: vehicle.vin) }
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    Task { await relay.lock(vin: vehicle.vin) }
                } label: {
                    Label("Lock", systemImage: "lock.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await relay.drive(vin: vehicle.vin) }
                } label: {
                    Label("Start Drive", systemImage: "steeringwheel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button {
                    Task { await relay.unlockAndDrive(vin: vehicle.vin) }
                } label: {
                    Label("Unlock & Drive", systemImage: "bolt.car").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if relay.pendingSchedule(for: vehicle.vin) != nil {
                    Button(role: .destructive) {
                        Task { await relay.cancelSchedule(vin: vehicle.vin) }
                    } label: {
                        Label("Cancel scheduled", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await relay.scheduleUnlockDrive(vin: vehicle.vin, delay: 60) }
                    } label: {
                        Label("Unlock & Drive in 60s", systemImage: "timer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Button {
                    Task { await relay.wake(vin: vehicle.vin) }
                } label: {
                    Label("Wake", systemImage: "sun.max").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                HStack {
                    Button {
                        Task { await relay.climateOn(vin: vehicle.vin) }
                    } label: {
                        Label("Climate", systemImage: "fan").frame(maxWidth: .infinity)
                    }
                    Button {
                        Task { await relay.climateOff(vin: vehicle.vin) }
                    } label: {
                        Label("Off", systemImage: "fan.slash").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption2)

                Button {
                    Task { await relay.refreshState(vin: vehicle.vin) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .font(.caption2)

                if let snap = relay.snapshot {
                    HStack(spacing: 10) {
                        if let b = snap.batteryLevel { Text("\(b)%") }
                        if let l = snap.locked { Text(l ? "Locked" : "Unlocked") }
                        if let o = snap.online { Text(o ? "Online" : "Asleep") }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if relay.pendingSchedule(for: vehicle.vin) != nil {
                    Label("Scheduled on server", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let status = relay.status {
                    Text(status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if let err = relay.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
            .disabled(relay.isBusy)
            .overlay { if relay.isBusy { ProgressView() } }
        }
        .task { await relay.refreshSchedules() }
    }

    /// Pre-2021 S/X have no BLE phone key — they're driven over the internet
    /// via the Fleet session the iPhone synced (unsigned commands).
    @ViewBuilder
    private var directCloudControls: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !cloud.hasSession {
                    cloudPrompt("Open EEAccess on your iPhone (Tesla Key) once while signed in to enable cloud control here.")
                } else {
                    Button {
                        Task { await cloud.unlock(vin: vehicle.vin) }
                    } label: {
                        Label("Unlock", systemImage: "lock.open.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        Task { await cloud.lock(vin: vehicle.vin) }
                    } label: {
                        Label("Lock", systemImage: "lock.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await cloud.startDrive(vin: vehicle.vin) }
                    } label: {
                        Label("Start Drive", systemImage: "steeringwheel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button {
                        Task { await cloud.unlockAndDrive(vin: vehicle.vin) }
                    } label: {
                        Label("Unlock & Drive", systemImage: "bolt.car").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    if let secs = cloud.scheduledSeconds {
                        Button(role: .destructive) {
                            cloud.cancelSchedule()
                        } label: {
                            Label("Cancel (\(secs)s)", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            cloud.scheduleUnlockDrive(vin: vehicle.vin, delay: 60)
                        } label: {
                            Label("Unlock & Drive in 60s", systemImage: "timer").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    Button {
                        Task { await cloud.wake(vin: vehicle.vin) }
                    } label: {
                        Label("Wake", systemImage: "sun.max").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    HStack {
                        Button {
                            Task { await cloud.climateOn(vin: vehicle.vin) }
                        } label: {
                            Label("Climate", systemImage: "fan").frame(maxWidth: .infinity)
                        }
                        Button {
                            Task { await cloud.climateOff(vin: vehicle.vin) }
                        } label: {
                            Label("Off", systemImage: "fan.slash").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)

                    Button {
                        Task { await cloud.refreshState(vin: vehicle.vin) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .font(.caption2)

                    if let snap = cloud.snapshot {
                        HStack(spacing: 10) {
                            if let b = snap.batteryLevel { Text("\(b)%") }
                            if let l = snap.locked { Text(l ? "Locked" : "Unlocked") }
                            if let o = snap.online { Text(o ? "Online" : "Asleep") }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    if cloud.hoursRemaining > 0 {
                        Label("Session good for ~\(cloud.hoursRemaining)h", systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let status = cloud.status {
                    Text(status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if let err = cloud.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
            .disabled(cloud.isBusy)
            .overlay { if cloud.isBusy { ProgressView() } }
        }
        .task { await cloud.ensureFreshToken() }
    }

    private func cloudPrompt(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var finishSetupPrompt: some View {
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
            NavigationLink("Finish Pairing", destination: WatchPairingView(vehicle: vehicle))
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @ViewBuilder
    private var controls: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                Button {
                    Task { if await key.unlock(vin: vehicle.vin) { bump() } }
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    Task { if await key.lock(vin: vehicle.vin) { bump() } }
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { if await key.startDrive(vin: vehicle.vin) { bump() } }
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

                Toggle(isOn: autoEntryBinding) {
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

                NavigationLink("Manage Key", destination: WatchPairingView(vehicle: vehicle))
                    .font(.caption2)
                    .padding(.top, 4)

                NavigationLink("Add another car", destination: WatchPairingView(vehicle: nil))
                    .font(.caption2)
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

    private var autoEntryBinding: Binding<Bool> {
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

    private var header: some View {
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

    private func bump() {
        vehicle.lastConnectedAt = .now
        try? context.save()
    }
}

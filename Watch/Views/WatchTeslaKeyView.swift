import SwiftUI
import SwiftData
import TeslaBLE

/// Tesla Key entry point on the watch. Routes by how many cars are set up:
/// none → setup prompt; one → straight to its controls; several → a picker
/// list. Per-car controls live in `WatchTeslaVehicleView`.
struct WatchTeslaKeyView: View {
    @Query(sort: \TeslaVehicle.createdAt) private var vehicles: [TeslaVehicle]

    var body: some View {
        Group {
            if vehicles.isEmpty {
                setupPrompt
            } else if vehicles.count == 1 {
                WatchTeslaVehicleView(vehicle: vehicles[0])
            } else {
                vehicleList
            }
        }
        .navigationTitle("Tesla Key")
    }

    private var vehicleList: some View {
        List {
            ForEach(vehicles) { vehicle in
                NavigationLink(destination: WatchTeslaVehicleView(vehicle: vehicle)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.displayName)
                            .font(.headline)
                        Text(subtitle(for: vehicle))
                            .font(.caption2)
                            .foregroundStyle(vehicle.isPaired ? .green : .secondary)
                    }
                }
            }
            NavigationLink(destination: WatchPairingView(vehicle: nil)) {
                Label("Add another car", systemImage: "plus.circle")
                    .font(.caption)
            }
        }
    }

    private func subtitle(for vehicle: TeslaVehicle) -> String {
        switch vehicle.accessMode {
        case .cloud: "Cloud — control from iPhone"
        case .bluetoothKey: vehicle.isPaired ? "Paired" : "Pending pairing"
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Set up your Tesla as a key")
                .font(.footnote)
                .multilineTextAlignment(.center)
            NavigationLink("Set Up Key", destination: WatchPairingView(vehicle: nil))
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

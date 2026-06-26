import SwiftUI
import SwiftData
import TeslaBLE

/// Pairing wizard + key management on the watch.
///
/// If the iPhone already synced a vehicle (VIN/name/role) this skips manual
/// entry and goes straight to the in-car pairing steps. Manual entry remains
/// as a fallback when no vehicle has been set up on the phone.
struct WatchPairingView: View {
    @Environment(\.modelContext) private var context
    @Environment(TeslaKeyService.self) private var key
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TeslaVehicle.createdAt) private var vehicles: [TeslaVehicle]

    @State private var vin = ""
    @State private var name = "Model X"
    @State private var useOwnerRole = false
    @State private var requestSent = false

    private var existing: TeslaVehicle? { vehicles.first }

    private var targetVIN: String {
        if let existing { return existing.vin }
        // VINs never contain I, O, or Q — strip them along with separators.
        return vin.uppercased().filter { ($0.isLetter || $0.isNumber) && !"IOQ".contains($0) }
    }

    private var targetRole: Command.KeyRole {
        if let existing { return existing.keyRoleRaw == "owner" ? .owner : .driver }
        return useOwnerRole ? .owner : .driver
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let existing, existing.isPaired {
                    managed(existing)
                } else if requestSent {
                    confirmStep
                } else {
                    startStep
                }
            }
            .padding(.horizontal, 6)
            .disabled(key.isBusy)
            .overlay {
                if key.isBusy { ProgressView() }
            }
        }
        .navigationTitle("Tesla Key")
        .onDisappear {
            // Abandoned mid-pairing: close the pairing-mode link so it can't
            // drain battery or shadow later commands. After a successful
            // Verify the flag is already cleared, so this is a no-op.
            if key.isPairingConnection {
                Task { await key.disconnect() }
            }
        }
    }

    // MARK: - Steps

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sit in your car with your physical Tesla key card. You don't need the Tesla app or the car's Add Key menu — after you start, you'll just tap that card on the console to authorize.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let existing {
                row("Car", existing.displayName)
                row("VIN", existing.vin)
                row("Role", existing.keyRoleRaw.capitalized)
            } else {
                field("VIN", text: $vin)
                field("Name", text: $name)
                Toggle("Owner (can manage keys)", isOn: $useOwnerRole)
                    .font(.caption2)
                Text("Tip: set the VIN on your iPhone (EEAccess → car icon) so you don't have to type it here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    if await key.sendPairingRequest(vin: targetVIN, role: targetRole) {
                        requestSent = true
                    }
                }
            } label: {
                Text("Start Pairing").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(targetVIN.count != 17)

            // Keychain keys survive app reinstall; the pairing record doesn't.
            // If a key for this VIN already exists it may still be enrolled on
            // the car — offer a direct Verify instead of re-pairing.
            if targetVIN.count == 17, key.hasKey(forVIN: targetVIN) {
                Button("Key already on this watch? Verify") {
                    Task {
                        if await key.verifyPairing(vin: targetVIN) {
                            finishPairing()
                            dismiss()
                        }
                    }
                }
                .font(.caption2)
            }
            footer
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Almost there")
                .font(.headline)
            Text("Stay next to the car. Tap your physical Tesla key card flat on the console reader (behind the cupholders / on the wireless charger). A \"Confirm new key\" prompt appears on the car's touchscreen — tap Confirm. Don't use the Add Key menu or the Tesla app. Only then tap Verify.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    if await key.verifyPairing(vin: targetVIN) {
                        finishPairing()
                        dismiss()
                    }
                }
            } label: {
                Text("Verify").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Back") { requestSent = false }
                .font(.caption2)
            footer
        }
    }

    private func managed(_ vehicle: TeslaVehicle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Name", vehicle.displayName)
            row("VIN", vehicle.vin)
            row("Role", vehicle.keyRoleRaw.capitalized)
            row("Status", vehicle.isPaired ? "Paired" : "Pending")
            Button(role: .destructive) {
                key.forgetKey(forVIN: vehicle.vin)
                vehicle.isPaired = false
                try? context.save()
                dismiss()
            } label: {
                Text("Forget Key").frame(maxWidth: .infinity)
            }
            footer
            Text("Forgetting only removes the key from this watch. To remove it from the car, use Controls ▸ Locks ▸ Keys on the car's screen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func finishPairing() {
        if let existing {
            existing.isPaired = true
            existing.lastConnectedAt = .now
        } else {
            let vehicle = TeslaVehicle(
                vin: targetVIN,
                displayName: name.isEmpty ? "Tesla" : name,
                isPaired: true,
                keyRoleRaw: useOwnerRole ? "owner" : "driver",
                lastConnectedAt: .now
            )
            context.insert(vehicle)
        }
        try? context.save()
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .monospaced()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let status = key.status {
            Text(status).font(.caption2).foregroundStyle(.secondary)
        }
        if let err = key.lastError {
            Text(err).font(.caption2).foregroundStyle(.red)
        }
    }
}

import SwiftUI
import SwiftData

@main
struct EEAccessApp: App {
    let container: ModelContainer
    @StateObject private var sync: PhoneSyncService
    @StateObject private var entitlement = EntitlementManager()
    @State private var fleetAuth = TeslaFleetAuth()
    @State private var fleet = TeslaFleetService()
    @State private var relay = RelayServerClient()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Card.self, TeslaVehicle.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.container = container
        _sync = StateObject(wrappedValue: PhoneSyncService(container: container))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if entitlement.isEntitled {
                    CardListView()
                } else {
                    PaywallView(trialEnded: true)
                }
            }
            .environmentObject(sync)
            .environmentObject(entitlement)
            .environment(fleetAuth)
            .environment(fleet)
            .environment(relay)
            .task {
                await entitlement.refreshEntitlement()
                await entitlement.loadProduct()
                await ShareInbox.processPendingShares(container: container, sync: sync)
                await syncTeslaSession()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await entitlement.refreshEntitlement()
                        await ShareInbox.processPendingShares(container: container, sync: sync)
                        await syncTeslaSession()
                    }
                }
            }
        }
        .modelContainer(container)
    }

    /// Pushes a fresh Fleet access token + region host to the watch so its
    /// cloud-car controls work standalone. No-op unless signed in.
    private func syncTeslaSession() async {
        guard fleetAuth.isSignedIn else { return }
        let base = await fleet.resolvedRegionBase(auth: fleetAuth)
        if let session = await fleetAuth.sessionForSync() {
            sync.sendTeslaCloudSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                expiresAt: session.expiresAt,
                baseURL: base,
                clientID: TeslaFleetConfig.clientID,
                clientSecret: TeslaFleetConfig.clientSecret
            )
        }
    }
}

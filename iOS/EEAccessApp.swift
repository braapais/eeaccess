import SwiftUI
import SwiftData

@main
struct EEAccessApp: App {
    let container: ModelContainer
    @StateObject private var sync: PhoneSyncService
    @StateObject private var entitlement = EntitlementManager()
    @State private var fleetAuth = TeslaFleetAuth()
    @State private var fleet = TeslaFleetService()
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
            .task {
                await entitlement.refreshEntitlement()
                await entitlement.loadProduct()
                await ShareInbox.processPendingShares(container: container, sync: sync)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await entitlement.refreshEntitlement()
                        await ShareInbox.processPendingShares(container: container, sync: sync)
                    }
                }
            }
        }
        .modelContainer(container)
    }
}

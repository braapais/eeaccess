import SwiftUI
import SwiftData

@main
struct EEAccessWatchApp: App {
    let container: ModelContainer
    @StateObject private var sync: WatchSyncService
    @State private var keyService = TeslaKeyService()

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Card.self, TeslaVehicle.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.container = container
        _sync = StateObject(wrappedValue: WatchSyncService(container: container))
    }

    var body: some Scene {
        WindowGroup {
            WatchCardListView()
                .environmentObject(sync)
                .environment(keyService)
        }
        .modelContainer(container)
    }
}

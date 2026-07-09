import SwiftUI
import SwiftData

@main
struct EEAccessWatchApp: App {
    let container: ModelContainer
    @StateObject private var sync: WatchSyncService
    @State private var keyService = TeslaKeyService()
    @State private var cloud = WatchTeslaCloud()

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
                .environment(cloud)
                .task(id: sync.teslaSession) { applySession() }
        }
        .modelContainer(container)
    }

    /// Feed the iPhone-synced Fleet session into the watch cloud client.
    private func applySession() {
        guard let s = sync.teslaSession else { return }
        cloud.applySession(accessToken: s.accessToken, expiresAt: s.expiresAt, baseURL: s.baseURL)
    }
}

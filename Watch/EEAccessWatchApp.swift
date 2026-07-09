import SwiftUI
import SwiftData

@main
struct EEAccessWatchApp: App {
    let container: ModelContainer
    @StateObject private var sync: WatchSyncService
    @State private var keyService = TeslaKeyService()
    @State private var cloud = WatchTeslaCloud()
    @Environment(\.scenePhase) private var scenePhase

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
                .task(id: sync.teslaSession) {
                    applySession()
                    await cloud.ensureFreshToken()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Opening the watch app refreshes the token directly over
                    // LTE/WiFi, so the user always has a fresh ~8 h window.
                    if phase == .active {
                        Task { await cloud.ensureFreshToken() }
                    }
                }
        }
        .modelContainer(container)
    }

    /// Feed the iPhone-synced Fleet session into the watch cloud client.
    private func applySession() {
        guard let s = sync.teslaSession else { return }
        cloud.applySession(
            accessToken: s.accessToken,
            refreshToken: s.refreshToken,
            expiresAt: s.expiresAt,
            baseURL: s.baseURL,
            clientID: s.clientID,
            clientSecret: s.clientSecret
        )
    }
}

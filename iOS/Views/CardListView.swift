import SwiftUI
import SwiftData

struct CardListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.lastUsedAt, order: .reverse) private var cards: [Card]
    @EnvironmentObject private var sync: PhoneSyncService
    @EnvironmentObject private var entitlement: EntitlementManager
    @State private var showingAdd = false
    @State private var showingPaywall = false
    @State private var showingCar = false
    @State private var syncMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trialBanner
                Group {
                    if cards.isEmpty {
                        ContentUnavailableView(
                            "No cards yet",
                            systemImage: "wallet.pass",
                            description: Text("Tap + to add a loyalty card, QR code, or membership card.")
                        )
                    } else {
                        List {
                            ForEach(cards) { card in
                                NavigationLink(value: card) {
                                    CardRowView(card: card)
                                }
                            }
                            .onMove(perform: move)
                            .onDelete(perform: delete)
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Wallet")
            .navigationDestination(for: Card.self) { CardDetailView(card: $0) }
            .task { CardOrdering.migrateLastUsedAtIfNeeded(context: context) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            let result = sync.resyncAll()
                            syncMessage = result.userMessage
                        } label: {
                            Label("Sync to Apple Watch", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(cards.isEmpty)
                        Button {
                            statusMessage = sync.currentStatus().summary
                        } label: {
                            Label("Watch Status", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "applewatch")
                    }
                    .accessibilityLabel("Apple Watch options")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCar = true } label: {
                        Image(systemName: "key.radiowaves.forward.fill")
                    }
                    .accessibilityLabel("Tesla Key")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add card")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddCardView()
            }
            .sheet(isPresented: $showingCar) {
                NavigationStack { TeslaKeySettingsView() }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(trialEnded: false)
            }
            .alert(
                "Sync to Apple Watch",
                isPresented: Binding(
                    get: { syncMessage != nil },
                    set: { if !$0 { syncMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) { syncMessage = nil } },
                message: { Text(syncMessage ?? "") }
            )
            .alert(
                "Watch Status",
                isPresented: Binding(
                    get: { statusMessage != nil },
                    set: { if !$0 { statusMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) { statusMessage = nil } },
                message: { Text(statusMessage ?? "") }
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            let card = cards[i]
            sync.sendDelete(id: card.id)
            context.delete(card)
        }
        try? context.save()
    }

    @ViewBuilder
    private var trialBanner: some View {
        if !entitlement.isPurchased && entitlement.isInTrial {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                    let n = entitlement.daysLeftInTrial
                    Text("Trial: \(n) day\(n == 1 ? "" : "s") left")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text("Unlock\(priceSuffix)")
                        .font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    private var priceSuffix: String {
        guard let price = entitlement.product?.displayPrice else { return "" }
        return " for \(price)"
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let movedCard = cards[sourceIndex]
        movedCard.lastUsedAt = CardOrdering.newTimestamp(
            for: cards,
            movingFrom: sourceIndex,
            to: destination
        )
        try? context.save()
        sync.sendUpsert(card: movedCard)
    }
}

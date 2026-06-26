import SwiftUI
import SwiftData

struct WatchCardListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.lastUsedAt, order: .reverse) private var cards: [Card]
    @State private var showCar = false

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Add cards on your iPhone")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        NavigationLink(destination: WatchTeslaKeyView()) {
                            Label("Tesla Key", systemImage: "key.radiowaves.forward.fill")
                                .font(.caption2)
                        }
                        .padding(.top, 4)
                        NavigationLink(destination: WatchStatusView()) {
                            Label("Status", systemImage: "info.circle")
                                .font(.caption2)
                        }
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            NavigationLink(destination: WatchTeslaKeyView()) {
                                Label("Tesla Key", systemImage: "key.radiowaves.forward.fill")
                            }
                        }
                        ForEach(cards) { card in
                            NavigationLink(value: card) {
                                HStack(spacing: 8) {
                                    WatchCardIcon(card: card)
                                    Text(card.name)
                                        .font(.body)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onMove(perform: move)
                        Section {
                            NavigationLink(destination: WatchStatusView()) {
                                Label("Status", systemImage: "info.circle")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wallet")
            .navigationDestination(for: Card.self) { WatchCardDetailView(card: $0) }
            .task { CardOrdering.migrateLastUsedAtIfNeeded(context: context) }
            .onOpenURL { url in
                if url.scheme == "eeaccess" { showCar = true }
            }
            .sheet(isPresented: $showCar) {
                NavigationStack { WatchTeslaKeyView() }
            }
        }
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
    }
}

private struct WatchCardIcon: View {
    let card: Card

    var body: some View {
        Group {
            if let data = card.iconImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: card.colorHex)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }
}

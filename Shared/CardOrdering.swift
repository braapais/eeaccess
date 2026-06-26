import Foundation
import SwiftData

/// Helpers for the "last-used floats to top, drag-to-reorder overrides position"
/// model. The list is sorted by `lastUsedAt` descending. Opening a card sets
/// it to `.now` (auto-promote). Dragging assigns a new midpoint timestamp so
/// the card lands at the user's chosen position without disturbing the others.
enum CardOrdering {
    /// Compute a new `lastUsedAt` for `cards[movedIndex]` given a destination
    /// position, where `cards` is the current visible-order array (already
    /// sorted by lastUsedAt descending).
    ///
    /// `destination` follows SwiftUI's `onMove` semantics: it's the offset
    /// before which the moved row will be inserted. If the row was at
    /// `source` and dragged downward, `destination` is one larger than the
    /// final visible index.
    static func newTimestamp(
        for cards: [Card],
        movingFrom source: Int,
        to destination: Int
    ) -> Date {
        guard !cards.isEmpty else { return .now }

        // Translate SwiftUI's drop offset into the actual final index.
        let finalIndex: Int
        if destination > source {
            finalIndex = destination - 1
        } else {
            finalIndex = destination
        }
        let clamped = max(0, min(finalIndex, cards.count - 1))

        // Build the post-move array and find the moved card's neighbors.
        var reordered = cards
        let moving = reordered.remove(at: source)
        reordered.insert(moving, at: clamped)

        let above: Date? = clamped > 0 ? reordered[clamped - 1].lastUsedAt : nil
        let below: Date? = clamped + 1 < reordered.count
            ? reordered[clamped + 1].lastUsedAt
            : nil

        switch (above, below) {
        case let (a?, b?):
            // Midpoint of neighbors. Treats Date as Double timestamps.
            let mid = (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2
            return Date(timeIntervalSince1970: mid)
        case (nil, _?):
            // Moved to the top — bump above current top by 1 second.
            return Date.now
        case let (a?, nil):
            // Moved to the bottom — drop just below current bottom.
            return a.addingTimeInterval(-1)
        case (nil, nil):
            return .now
        }
    }

    /// One-shot migration for cards persisted before `lastUsedAt` existed —
    /// they come back with the `Date.distantPast` default. Set them to their
    /// own `createdAt` so existing card collections retain their original
    /// order until the user starts using/reordering.
    @MainActor
    static func migrateLastUsedAtIfNeeded(context: ModelContext) {
        let sentinel = Date.distantPast
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate { $0.lastUsedAt == sentinel }
        )
        guard let cards = try? context.fetch(descriptor), !cards.isEmpty else { return }
        for card in cards {
            card.lastUsedAt = card.createdAt
        }
        try? context.save()
    }
}

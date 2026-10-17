import Foundation
import SwiftData
import UIKit

/// Reads `PendingShare` JSON files written by the Share Extension into the
/// App Group container, turns each one into a `Card` (decoding as a barcode
/// when possible, otherwise treating the image as the card photo), syncs
/// the new card to the watch, and removes the processed file.
enum ShareInbox {
    @MainActor
    static func processPendingShares(container: ModelContainer, sync: PhoneSyncService) async {
        guard let dir = AppGroup.pendingSharesDirectory else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        let decoder = PendingShare.decoder()
        for fileURL in files where fileURL.pathExtension == "json" {
            // Claim (read + remove) the file before any `await` below. This
            // runs on launch AND on scenePhase→active, which race on a cold
            // launch; removing it synchronously up front means a concurrent
            // call sees the file already gone instead of re-ingesting it and
            // inserting a duplicate card.
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            try? fm.removeItem(at: fileURL)
            guard let share = try? decoder.decode(PendingShare.self, from: data) else {
                continue
            }
            await ingest(share, container: container, sync: sync)
        }
    }

    @MainActor
    private static func ingest(_ share: PendingShare, container: ModelContainer, sync: PhoneSyncService) async {
        let decoded = await BarcodeDecoder.decode(data: share.imageData)
        let card: Card

        if let decoded {
            let normalized = await ImageProcessing.normalizeOffMain(
                data: share.imageData, maxDimension: 800, quality: 0.85
            )
            card = Card(
                name: share.name,
                barcodeValue: decoded.value,
                barcodeType: decoded.type,
                barcodeImageData: normalized,
                imageData: nil,
                iconImageData: nil,
                createdAt: share.createdAt
            )
        } else {
            let normalized = await ImageProcessing.normalizeOffMain(
                data: share.imageData, maxDimension: 1024, quality: 0.6
            )
            card = Card(
                name: share.name,
                barcodeValue: nil,
                barcodeType: "qr",
                barcodeImageData: nil,
                imageData: normalized,
                iconImageData: nil,
                createdAt: share.createdAt
            )
        }

        let context = container.mainContext
        context.insert(card)
        try? context.save()
        sync.sendUpsert(card: card)
    }
}

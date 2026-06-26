import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the iOS Share Extension. Loads the shared image from
/// the host app, then hosts a SwiftUI form that lets the user name the
/// card before saving it to the App Group container as a `PendingShare`.
/// The main app picks it up on next launch.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadSharedImage()
    }

    private func loadSharedImage() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            close()
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data else {
                    self.close()
                    return
                }
                self.presentShareUI(imageData: data)
            }
        }
    }

    private func presentShareUI(imageData: Data) {
        let view = ShareExtensionView(
            imageData: imageData,
            onCancel: { [weak self] in self?.close() },
            onSave: { [weak self] name in
                guard let self else { return }
                self.savePendingShare(name: name, imageData: imageData)
                self.close()
            }
        )
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func savePendingShare(name: String, imageData: Data) {
        guard let dir = AppGroup.pendingSharesDirectory else { return }
        let share = PendingShare(
            id: UUID(),
            createdAt: .now,
            name: name,
            imageData: imageData
        )
        let url = dir.appendingPathComponent("\(share.id.uuidString).json")
        if let data = try? PendingShare.encoder().encode(share) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

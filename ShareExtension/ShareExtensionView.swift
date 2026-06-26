import SwiftUI
import UIKit

struct ShareExtensionView: View {
    let imageData: Data
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let img = UIImage(data: imageData) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 220)
                    }
                } header: {
                    Text("Image")
                } footer: {
                    Text("If this is a barcode, EEAccess will decode it automatically when you open the app.")
                }
                Section("Card name") {
                    TextField("e.g. Starbucks, Gym, Pingo Doce", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Save to EEAccess")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

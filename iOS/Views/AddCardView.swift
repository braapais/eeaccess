import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

private struct BarcodeTypeOption: Identifiable, Hashable {
    let id: String
    let label: String
}

private struct SearchID: Hashable {
    let query: String
    let country: String
}

private enum ActiveSheet: Identifiable {
    case scanner
    case cropLogo(LogoCropSource)

    var id: String {
        switch self {
        case .scanner: return "scanner"
        case .cropLogo(let s): return "crop-\(s.id.uuidString)"
        }
    }
}

struct AddCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: PhoneSyncService

    private let editingCard: Card?

    @State private var name: String
    @State private var barcodeValue: String
    @State private var barcodeType: String
    @State private var colorHex: String
    @State private var imageData: Data?
    @State private var iconImageData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var iconPickerItem: PhotosPickerItem?

    @State private var pastedBarcodeImageData: Data?
    @State private var decodingPaste = false

    @State private var logoQuery = ""
    @State private var searchCountry: String = AppStoreRegion.defaultCode()
    @State private var searchResults: [AppStoreResult] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var applyingResultID: String?

    @State private var activeSheet: ActiveSheet?

    init(editingCard: Card? = nil) {
        self.editingCard = editingCard
        if let card = editingCard {
            _name = State(initialValue: card.name)
            _barcodeValue = State(initialValue: card.barcodeValue ?? "")
            _barcodeType = State(initialValue: card.barcodeType)
            _colorHex = State(initialValue: card.colorHex)
            _imageData = State(initialValue: card.imageData)
            _iconImageData = State(initialValue: card.iconImageData)
            // Restore pasted barcode image only when the type can't be re-rendered
            // from the value (e.g. EAN-13). Renderable types are rebuilt at save.
            if !BarcodeRenderer.canRender(type: card.barcodeType) {
                _pastedBarcodeImageData = State(initialValue: card.barcodeImageData)
            } else {
                _pastedBarcodeImageData = State(initialValue: nil)
            }
        } else {
            _name = State(initialValue: "")
            _barcodeValue = State(initialValue: "")
            _barcodeType = State(initialValue: "qr")
            _colorHex = State(initialValue: "#3B82F6")
            _imageData = State(initialValue: nil)
            _iconImageData = State(initialValue: nil)
            _pastedBarcodeImageData = State(initialValue: nil)
        }
    }

    private let colors = [
        "#3B82F6", "#EF4444", "#10B981", "#F59E0B",
        "#8B5CF6", "#EC4899", "#0EA5E9", "#111827"
    ]
    private let barcodeTypes: [BarcodeTypeOption] = [
        BarcodeTypeOption(id: "qr", label: "QR Code"),
        BarcodeTypeOption(id: "code128", label: "Code 128"),
        BarcodeTypeOption(id: "pdf417", label: "PDF417"),
        BarcodeTypeOption(id: "aztec", label: "Aztec")
    ]

    var body: some View {
        NavigationStack {
            Form {
                cardSection
                logoSection
                barcodeAndImageSection
            }
            .navigationTitle(editingCard == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: photoPickerItem) { _, item in
                Task { await loadImageOrBarcode(from: item) }
            }
            .onChange(of: iconPickerItem) { _, item in
                Task { await loadIcon(from: item) }
            }
            .onChange(of: name) { _, newName in
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                logoQuery = trimmed
            }
            .task(id: SearchID(query: logoQuery, country: searchCountry)) { await runSearch() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .scanner:
                    ScannerView { value, type in
                        barcodeValue = value
                        barcodeType = type
                        activeSheet = nil
                    }
                    .ignoresSafeArea()
                case .cropLogo(let source):
                    LogoCropView(source: source) { croppedData in
                        iconImageData = croppedData
                        activeSheet = nil
                    } onCancel: {
                        activeSheet = nil
                    }
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var logoSection: some View {
        Section {
            logoUploadRow
            logoSearchField
            logoSearchResults
        } header: {
            Text("Logo")
        } footer: {
            Text("Search the App Store for an app's icon, paste from the clipboard, or upload from Photos.")
        }
    }

    @ViewBuilder
    private var logoSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search the App Store", text: $logoQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if searching {
                ProgressView().controlSize(.small)
            } else if !logoQuery.isEmpty {
                Button {
                    logoQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            regionMenu
        }
    }

    @ViewBuilder
    private var regionMenu: some View {
        Menu {
            ForEach(AppStoreRegion.common) { region in
                Button {
                    searchCountry = region.code
                } label: {
                    HStack {
                        Text("\(AppStoreRegion.flagEmoji(for: region.code))  \(region.name) (\(region.code.uppercased()))")
                        if region.code == searchCountry {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("\(AppStoreRegion.flagEmoji(for: searchCountry)) \(searchCountry.uppercased())")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var logoSearchResults: some View {
        if let searchError {
            Text(searchError)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !searchResults.isEmpty {
            AppStoreResultsStrip(
                results: searchResults,
                applyingResultID: applyingResultID,
                onApply: { result in
                    Task { await applyResult(result) }
                }
            )
        }
    }

    @ViewBuilder
    private var logoUploadRow: some View {
        HStack(spacing: 16) {
            LogoPreview(iconData: iconImageData, fallbackHex: colorHex)
            Spacer()
            HStack(spacing: 22) {
                PhotosPicker(selection: $iconPickerItem, matching: .images) {
                    Label("Upload from Photos", systemImage: "photo.on.rectangle")
                }
                .labelStyle(.iconOnly)
                .font(.title2)

                PasteButton(supportedContentTypes: [.image]) { providers in
                    handlePastedImage(providers: providers)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)

                if let data = iconImageData {
                    Button {
                        activeSheet = .cropLogo(LogoCropSource(data: data))
                    } label: {
                        Label("Adjust crop", systemImage: "crop")
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)

                    Button(role: .destructive) {
                        iconImageData = nil
                        iconPickerItem = nil
                    } label: {
                        Label("Remove logo", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cardSection: some View {
        Section("Card") {
            TextField("Name (e.g. Gym, Starbucks)", text: $name)
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { c in
                    ColorSwatch(hex: c, selected: colorHex == c) {
                        colorHex = c
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var barcodeAndImageSection: some View {
        Section {
            Picker("Type", selection: $barcodeType) {
                ForEach(barcodeTypes) { option in
                    Text(option.label).tag(option.id)
                }
            }
            TextField("Code value (optional)", text: $barcodeValue)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                activeSheet = .scanner
            } label: {
                Label("Scan with camera", systemImage: "barcode.viewfinder")
            }
            HStack(spacing: 22) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label("Upload from Photos", systemImage: "photo.on.rectangle")
                }
                .labelStyle(.iconOnly)
                .font(.title2)

                PasteButton(supportedContentTypes: [.image]) { providers in
                    handlePastedImageOrBarcode(providers: providers)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)

                Spacer()
            }
            barcodeDecodeIndicator
            pastedBarcodePreview
            cardImagePreview
        } header: {
            Text("Barcode & image")
        } footer: {
            Text("Scan a barcode, type a code, or upload/paste an image. We try to decode any image as a barcode first; if that fails, we save it as the card image.")
        }
    }

    @ViewBuilder
    private var barcodeDecodeIndicator: some View {
        if decodingPaste {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading barcode…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pastedBarcodePreview: some View {
        if let data = pastedBarcodeImageData, let img = UIImage(data: data) {
            HStack(alignment: .center, spacing: 12) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 80)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pasted barcode")
                        .font(.caption)
                    Text(BarcodeRenderer.canRender(type: barcodeType)
                        ? "Saved as-is so styling is preserved. Remove to render fresh from the code value."
                        : "Type \(barcodeType.uppercased()) — saved as-is.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    pastedBarcodeImageData = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var cardImagePreview: some View {
        if let imageData, let img = UIImage(data: imageData) {
            VStack(alignment: .leading, spacing: 8) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                Button("Remove image", role: .destructive) {
                    self.imageData = nil
                    self.photoPickerItem = nil
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save", action: save).disabled(!canSave)
        }
    }

    // MARK: Validation + I/O

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !barcodeValue.isEmpty
            || imageData != nil
            || pastedBarcodeImageData != nil
            || iconImageData != nil
    }

    private func loadImageOrBarcode(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await processImageOrBarcode(data: data)
    }

    private func loadIcon(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        activeSheet = .cropLogo(LogoCropSource(data: data))
    }

    private func handlePastedImage(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                activeSheet = .cropLogo(LogoCropSource(data: data))
                iconPickerItem = nil
            }
        }
    }

    private func handlePastedImageOrBarcode(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                await processImageOrBarcode(data: data)
            }
        }
    }

    /// Try to decode the image as a barcode first; if that succeeds, populate
    /// the barcode value/type AND keep the original image — its styling
    /// (logo overlays, brand color, custom design) can't be reproduced by
    /// our generator, so we save it as-is. If decode fails, the image becomes
    /// the card photo (`imageData`).
    @MainActor
    private func processImageOrBarcode(data: Data) async {
        decodingPaste = true
        let decoded = await BarcodeDecoder.decode(data: data)
        decodingPaste = false

        if let decoded {
            barcodeValue = decoded.value
            barcodeType = decoded.type
            pastedBarcodeImageData = await ImageProcessing.normalizeOffMain(
                data: data, maxDimension: 800, quality: 0.85
            )
        } else {
            imageData = await ImageProcessing.normalizeOffMain(
                data: data, maxDimension: 1024, quality: 0.6
            )
        }
        photoPickerItem = nil
    }

    // MARK: App Store search

    @MainActor
    private func runSearch() async {
        let trimmed = logoQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            searchError = nil
            searching = false
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        searching = true
        searchError = nil
        defer { searching = false }

        do {
            let results = try await AppStoreSearchService.search(query: trimmed, country: searchCountry)
            guard !Task.isCancelled else { return }
            searchResults = results
            if results.isEmpty {
                searchError = "No apps found."
            }
        } catch AppStoreSearchService.SearchError.http(let code) {
            searchError = "Search failed (HTTP \(code))."
            searchResults = []
        } catch {
            searchError = "Search failed."
            searchResults = []
        }
    }

    @MainActor
    private func applyResult(_ result: AppStoreResult) async {
        applyingResultID = result.id
        defer { applyingResultID = nil }
        do {
            let data = try await AppStoreSearchService.fetchImageData(from: result.highResURL)
            activeSheet = .cropLogo(LogoCropSource(data: data))
            iconPickerItem = nil
        } catch {
            searchError = "Couldn't download that icon."
        }
    }

    // MARK: Save

    private func save() {
        let trimmedValue = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedValue = trimmedValue.isEmpty ? nil : trimmedValue

        let renderedFromValue: Data? = {
            guard let value = storedValue,
                  BarcodeRenderer.canRender(type: barcodeType),
                  let img = BarcodeRenderer.render(
                    value: value,
                    type: barcodeType,
                    size: renderSize(for: barcodeType)
                  ) else { return nil }
            return img.pngData()
        }()
        // Prefer the user's pasted/scanned image when present — it preserves
        // any styling our renderer can't reproduce. Fall back to the fresh
        // render when the user only typed a value.
        let finalBarcodeImage = pastedBarcodeImageData ?? renderedFromValue
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        let card: Card
        if let existing = editingCard {
            existing.name = trimmedName
            existing.barcodeValue = storedValue
            existing.barcodeType = barcodeType
            existing.barcodeImageData = finalBarcodeImage
            existing.imageData = imageData
            existing.iconImageData = iconImageData
            existing.colorHex = colorHex
            card = existing
        } else {
            card = Card(
                name: trimmedName,
                barcodeValue: storedValue,
                barcodeType: barcodeType,
                barcodeImageData: finalBarcodeImage,
                imageData: imageData,
                iconImageData: iconImageData,
                colorHex: colorHex
            )
            context.insert(card)
        }
        try? context.save()
        sync.sendUpsert(card: card)
        dismiss()
    }

    private func renderSize(for type: String) -> CGSize {
        switch type.lowercased() {
        case "qr", "aztec": return CGSize(width: 600, height: 600)
        default: return CGSize(width: 800, height: 240)
        }
    }
}

private struct ColorSwatch: View {
    let hex: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().stroke(Color.primary, lineWidth: selected ? 3 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct LogoPreview: View {
    let iconData: Data?
    let fallbackHex: String

    var body: some View {
        Group {
            if let data = iconData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: fallbackHex)
                    .overlay(
                        Image(systemName: "building.2")
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }
}

private struct AppStoreResultsStrip: View {
    let results: [AppStoreResult]
    let applyingResultID: String?
    let onApply: (AppStoreResult) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(results) { result in
                    AppStoreResultThumbnail(
                        result: result,
                        applying: applyingResultID == result.id,
                        onTap: { onApply(result) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct AppStoreResultThumbnail: View {
    let result: AppStoreResult
    let applying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    AsyncImage(url: result.thumbnailURL) { phase in
                        switch phase {
                        case .empty:
                            Color.gray.opacity(0.15)
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Color.gray.opacity(0.2)
                                .overlay(
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .foregroundStyle(.secondary)
                                )
                        @unknown default:
                            Color.gray.opacity(0.15)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    if applying {
                        Color.black.opacity(0.4)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
                Text(result.trackName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
        .buttonStyle(.plain)
        .disabled(applying)
    }
}


import Foundation

struct AppStoreResult: Identifiable, Hashable, Sendable {
    let id: String
    let trackName: String
    let sellerName: String
    let thumbnailURL: URL
    let highResURL: URL
}

struct AppStoreRegion: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    var id: String { code }

    static let common: [AppStoreRegion] = [
        AppStoreRegion(code: "us", name: "United States"),
        AppStoreRegion(code: "gb", name: "United Kingdom"),
        AppStoreRegion(code: "pt", name: "Portugal"),
        AppStoreRegion(code: "es", name: "Spain"),
        AppStoreRegion(code: "fr", name: "France"),
        AppStoreRegion(code: "de", name: "Germany"),
        AppStoreRegion(code: "it", name: "Italy"),
        AppStoreRegion(code: "ie", name: "Ireland"),
        AppStoreRegion(code: "nl", name: "Netherlands"),
        AppStoreRegion(code: "br", name: "Brazil"),
        AppStoreRegion(code: "mx", name: "Mexico"),
        AppStoreRegion(code: "ca", name: "Canada"),
        AppStoreRegion(code: "au", name: "Australia"),
        AppStoreRegion(code: "jp", name: "Japan"),
    ]

    static func defaultCode() -> String {
        (Locale.current.region?.identifier ?? "US").lowercased()
    }

    static func flagEmoji(for code: String) -> String {
        let base: UInt32 = 127397
        var s = ""
        for v in code.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + v.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s
    }
}

enum AppStoreSearchService {
    enum SearchError: Error {
        case http(Int)
        case decoding
        case network(Error)
    }

    /// iTunes Search API — public, no API key, no quota worth worrying about.
    /// Returns iOS App Store results filtered to apps (`media=software`),
    /// in the requested region (or the device's region by default).
    static func search(query: String, country: String? = nil, limit: Int = 20) async throws -> [AppStoreResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let country = (country ?? Locale.current.region?.identifier ?? "US").lowercased()

        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SearchError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SearchError.http(status) }

        // Parse off-main: even small JSON decoding on the main actor while the
        // user is mid-typing causes the keyboard to log "Result accumulator
        // timeout" warnings.
        return try await Task.detached(priority: .userInitiated) {
            try parseResults(from: data)
        }.value
    }

    static func fetchImageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SearchError.http(status) }
        return data
    }

    private static func parseResults(from data: Data) throws -> [AppStoreResult] {
        let decoded: ITunesResponse
        do {
            decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
        } catch {
            throw SearchError.decoding
        }
        var seen = Set<String>()
        var results: [AppStoreResult] = []
        for r in decoded.results {
            // Prefer trackId for unique identity since it's stable across regions
            // and bundle id can be missing for some legacy results.
            let id = r.trackId.map(String.init) ?? r.bundleId ?? r.trackName ?? UUID().uuidString
            guard seen.insert(id).inserted else { continue }
            guard let thumbStr = r.artworkUrl100 ?? r.artworkUrl60,
                  let thumb = URL(string: thumbStr),
                  let highStr = r.artworkUrl512 ?? r.artworkUrl100 ?? r.artworkUrl60,
                  let high = URL(string: highStr) else { continue }
            results.append(AppStoreResult(
                id: id,
                trackName: r.trackName ?? "",
                sellerName: r.sellerName ?? "",
                thumbnailURL: thumb,
                highResURL: high
            ))
        }
        return results
    }

    private struct ITunesResponse: Decodable {
        let results: [ResultItem]
        struct ResultItem: Decodable {
            let trackId: Int?
            let trackName: String?
            let sellerName: String?
            let bundleId: String?
            let artworkUrl60: String?
            let artworkUrl100: String?
            let artworkUrl512: String?
        }
    }
}

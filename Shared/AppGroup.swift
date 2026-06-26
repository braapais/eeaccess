import Foundation

enum AppGroup {
    static let identifier = "group.com.elbaeverywhere.eeaccess"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var pendingSharesDirectory: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("pending-shares", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

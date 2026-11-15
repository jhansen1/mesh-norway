import CryptoKit
import Foundation

/// A saved answer from the site.
struct SavedResponse: Equatable, Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data
}

/// Saved copies of the site's answers, on disk, so the app opens with the last
/// data it received when there is no connection. Each store keeps under a size
/// budget by dropping the copies that were used longest ago.
///
/// It lives in the Caches directory: the system may empty it when the device
/// runs short of space, and nothing in it is needed for the app to work online.
@MainActor
final class OfflineStore {
    private struct Meta: Codable {
        var key: String
        var status: Int
        var headers: [String: String]
    }

    private let directory: URL
    private let budgetBytes: Int
    private let maxEntryBytes: Int
    private let files = FileManager.default

    /// The largest answer this store keeps.
    var entryLimit: Int { maxEntryBytes }

    init(directory: URL, budgetBytes: Int, maxEntryBytes: Int) {
        self.directory = directory
        self.budgetBytes = budgetBytes
        self.maxEntryBytes = maxEntryBytes
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A store in the app's Caches directory.
    convenience init(name: String, budgetBytes: Int, maxEntryBytes: Int) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(directory: caches.appendingPathComponent("OfflineStore", isDirectory: true).appendingPathComponent(name, isDirectory: true),
                  budgetBytes: budgetBytes, maxEntryBytes: maxEntryBytes)
    }

    func contains(_ key: String) -> Bool {
        files.fileExists(atPath: metaURL(key).path) && files.fileExists(atPath: bodyURL(key).path)
    }

    func read(_ key: String) -> SavedResponse? {
        guard let metaData = try? Data(contentsOf: metaURL(key)),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
              meta.key == key,
              let body = try? Data(contentsOf: bodyURL(key)) else { return nil }
        // Used now: last in line when the store needs room.
        try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: bodyURL(key).path)
        return SavedResponse(status: meta.status, headers: meta.headers, body: body)
    }

    func write(_ response: SavedResponse, for key: String) {
        guard response.body.count <= maxEntryBytes,
              let metaData = try? JSONEncoder().encode(Meta(key: key, status: response.status, headers: response.headers)) else { return }
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try response.body.write(to: bodyURL(key), options: .atomic)
            try metaData.write(to: metaURL(key), options: .atomic)
        } catch {
            // Half a copy is no copy.
            remove(key)
            return
        }
        prune()
    }

    func remove(_ key: String) {
        try? files.removeItem(at: bodyURL(key))
        try? files.removeItem(at: metaURL(key))
    }

    func removeAll() {
        try? files.removeItem(at: directory)
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Bytes of saved bodies.
    func totalBytes() -> Int {
        bodies().reduce(0) { $0 + $1.size }
    }

    private func prune() {
        var entries = bodies()
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > budgetBytes else { return }
        entries.sort { $0.used < $1.used }
        for entry in entries {
            if total <= budgetBytes { break }
            try? files.removeItem(at: entry.url)
            try? files.removeItem(at: entry.url.deletingPathExtension().appendingPathExtension("meta"))
            total -= entry.size
        }
    }

    private func bodies() -> [(url: URL, size: Int, used: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "body", let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private func name(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func bodyURL(_ key: String) -> URL { directory.appendingPathComponent(name(key) + ".body") }
    private func metaURL(_ key: String) -> URL { directory.appendingPathComponent(name(key) + ".meta") }
}

import Foundation

/// One entry of the Recent list: a file that finished transferring.
struct RecentTransfer: Codable, Equatable {
    enum Kind: String, Codable {
        /// Uploaded from this Mac.
        case upload
        /// Downloaded to this Mac while SyncGlass watched the download.
        case download
        /// Changed on another device and already current when SyncGlass checked it.
        case change

        var verb: String {
            switch self {
            case .upload: return "Uploaded"
            case .download: return "Downloaded"
            case .change: return "Synced"
            }
        }
    }

    var path: String
    /// When SyncGlass saw the transfer finish.
    var date: Date
    var kind: Kind
}

/// Reads and writes the Recent list (`recent_transfers.plist` in `Paths.supportFolder`).
enum RecentTransfersStore {
    static var url: URL { Paths.supportFolder.appendingPathComponent("recent_transfers.plist") }

    static func load() -> [RecentTransfer] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? PropertyListDecoder().decode([RecentTransfer].self, from: data)) ?? []
    }

    static func save(_ entries: [RecentTransfer]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

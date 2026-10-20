import Foundation

/// Byte progress of one file that iCloud is uploading or downloading.
struct FileProgress: Equatable {
    enum Direction { case uploading, downloading }

    var direction: Direction?
    var fraction: Double
    var completedBytes: Int64
    var totalBytes: Int64
}

/// Per-file upload and download progress, from the `Progress` objects that the
/// iCloud Drive file provider publishes for files it transfers.
///
/// Measured on macOS 27:
/// - These progress objects report bytes from 0 to 100 % during uploads and
///   downloads. `NSURLUbiquitousItemPercentUploadedKey` stays nil, and an
///   `NSMetadataQuery` on the folder returns no items.
/// - `Progress.addSubscriber(forFileURL:)` on a folder only receives the progress
///   of files directly inside it, not in subfolders, and the progress objects it
///   receives do not always carry `NSProgressFileURLKey`.
///
/// So the monitor subscribes to each file in flight, which ties every progress
/// object to a known path.
final class FileProgressMonitor: @unchecked Sendable {
    /// Upper bound on subscriptions during a large sync.
    static let maxSubscriptions = 500

    private let lock = NSLock()
    private var subscriptions: [String: Any] = [:]
    private var progresses: [String: Progress] = [:]

    deinit { track([]) }

    /// Subscribe to the paths in flight and drop the subscriptions of paths that finished.
    func track(_ paths: Set<String>) {
        let wanted = Set(paths.prefix(Self.maxSubscriptions))
        let (added, removed): ([String], [Any]) = withLock {
            let stale = subscriptions.filter { !wanted.contains($0.key) }
            for path in stale.keys {
                subscriptions[path] = nil
                progresses[path] = nil
            }
            return (wanted.filter { subscriptions[$0] == nil }, Array(stale.values))
        }
        removed.forEach(Progress.removeSubscriber)

        for path in added {
            let token = Progress.addSubscriber(forFileURL: URL(fileURLWithPath: path)) { [weak self] progress in
                self?.withLock { self?.progresses[path] = progress }
                return { [weak self] in
                    self?.withLock {
                        if self?.progresses[path] === progress { self?.progresses[path] = nil }
                    }
                }
            }
            withLock { subscriptions[path] = token }
        }
    }

    /// Progress of the tracked files that iCloud is transferring now.
    func progressByPath() -> [String: FileProgress] {
        let current = withLock { progresses }
        return current.mapValues { p in
            let direction: FileProgress.Direction?
            switch p.fileOperationKind {
            case .uploading?: direction = .uploading
            case .downloading?: direction = .downloading
            default: direction = nil
            }
            return FileProgress(
                direction: direction,
                fraction: min(1, max(0, p.fractionCompleted)),
                completedBytes: p.completedUnitCount,
                totalBytes: p.totalUnitCount)
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

import FileProvider
import Foundation
import Observation

/// One item in iCloud Drive's queue of unsynced items, as `brctl status` prints it
/// under "Client Truth Unclean Items".
///
/// `brctl` is undocumented and its output can change with macOS. Measured on macOS 27:
///
///     <c{1}m.a{3}e.C{7}s[1] foreground {client:needs-sync …}>
///         Client Truth Unclean Items:
///         --------------------------
///         Under /SyncGlass offline test
///             r:3389463 i:<816F941B> al:1 foid:<f33b817> ld{synced-all} up:needs-upload uv:1 st{p:<69AF9158> n:"o{10}t.bin" doc …} up-id{fid:502868389, gen:1} ct{mt:1792963456 sz:314.6 MB (314572800) …}
///             > upload{[ active attempts:0 last:1.10m ago next:ready cleanup:58.88m]}
///
/// The container identifier and the names are abbreviated to their first and last
/// character and the count in between ("o{10}t.bin" for "offline-test.bin"); the
/// folder path is printed in full. `foid` is the File Provider item identifier,
/// which `NSFileProviderManager.getIdentifierForUserVisibleFile(at:)` returns for
/// the file. `up-id` is the inode of the copy that the iCloud Drive daemon uploads
/// (`~/Library/Application Support/CloudDocs/session/i/<foid>.bin`), not of the file.
struct QueueItem: Equatable {
    /// The abbreviated container identifier, "c{1}m.a{3}e.C{7}s" for com.apple.CloudDocs.
    var container: String
    /// The folder relative to the container, "/SyncGlass offline test".
    var folder: String
    /// The abbreviated name, "o{10}t.bin".
    var name: String
    var isDirectory: Bool
    var size: Int64?
    var fileProviderID: String
    /// The `up:` field, such as "needs-upload" or "needs-sync-up".
    var state: String?
    var operation: Operation?

    struct Operation: Equatable {
        /// "upload", "sync-up", …
        var kind: String
        var attempts: Int?
        var lastAttempt: Date?
    }
}

enum ICloudQueue {
    /// Runs `brctl status`. It takes about 4 s, because it waits for the iCloud
    /// Drive daemon. A run that has not finished after 60 s is stopped.
    static func readStatus() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        p.arguments = ["status"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            if p.isRunning { p.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// The items of `brctl status` output. `now` is when `brctl` ran; the times of
    /// the last attempts are relative to it.
    static func parse(_ output: String, now: Date = Date()) -> [QueueItem] {
        let text = output.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        var items: [QueueItem] = []
        var container = ""
        var folder: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("<"), let end = line.firstIndex(of: "[") {
                container = String(line[line.index(after: line.startIndex)..<end])
                folder = nil
            } else if line.hasPrefix("Under ") {
                folder = String(line.dropFirst("Under ".count))
            } else if let folder, let id = capture(line, #/foid:<([^>]+)>/#) {
                items.append(QueueItem(
                    container: container,
                    folder: folder,
                    name: capture(line, #/n:"([^"]*)"/#) ?? "",
                    isDirectory: line.contains(" dir "),
                    size: capture(line, #/sz:[^(]*\((\d+)\)/#).flatMap { Int64($0) },
                    fileProviderID: id,
                    state: capture(line, #/ up:([\w-]+)/#)))
            } else if line.hasPrefix(">"), let kind = capture(line, #/^>\s*([\w-]+)\{/#),
                      !items.isEmpty, items[items.count - 1].operation == nil
            {
                var lastAttempt: Date?
                if let m = line.firstMatch(of: #/last:([\d.]+)([smhd]) ago/#), let value = Double(m.1) {
                    let unit: Double = ["s": 1, "m": 60, "h": 3600, "d": 86400][String(m.2)] ?? 1
                    lastAttempt = now.addingTimeInterval(-value * unit)
                }
                items[items.count - 1].operation = QueueItem.Operation(
                    kind: kind,
                    attempts: capture(line, #/attempts:(\d+)/#).flatMap { Int($0) },
                    lastAttempt: lastAttempt)
            }
        }
        return items
    }

    /// Whether `name` fits a name abbreviated by `brctl`: the first character, the
    /// last character before the extension, and the extension ("o{10}t.bin" for
    /// "offline-test.bin"). The count in braces is not compared, because it is not
    /// known whether `brctl` counts characters or bytes. A name without braces is
    /// compared in full.
    static func matchesAbbreviation(_ name: String, _ abbreviation: String) -> Bool {
        guard let m = abbreviation.firstMatch(of: #/^(.)\{\d+\}(.)(.*)$/#) else { return name == abbreviation }
        return name.hasPrefix(m.1) && name.hasSuffix(m.2 + m.3) && name.count >= 2 + m.3.count
    }

    /// Whether a container identifier, such as "com.apple.CloudDocs", fits its
    /// abbreviation, "c{1}m.a{3}e.C{7}s": each dot-separated part is abbreviated.
    static func matchesContainer(_ identifier: String, _ abbreviation: String) -> Bool {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        let short = abbreviation.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == short.count else { return false }
        return zip(parts, short).allSatisfy { part, abbr in
            guard let m = abbr.firstMatch(of: #/^(.)\{(\d+)\}(.)$/#), let n = Int(m.2) else { return part == abbr }
            return part.count == n + 2 && part.hasPrefix(m.1) && part.hasSuffix(m.3)
        }
    }

    /// The file an item refers to. Lists the item's folder in each container whose
    /// identifier fits the abbreviation, keeps the entries whose name fits, and
    /// returns the one with the item's File Provider identifier. In iCloud Drive,
    /// Desktop and Documents are symbolic links to ~/Desktop and ~/Documents; the
    /// path is returned with links resolved, as FSEvents reports it.
    static func resolve(_ item: QueueItem) async -> String? {
        let containers = (try? FileManager.default.contentsOfDirectory(atPath: Paths.mobileDocuments)) ?? []
        for dir in containers where matchesContainer(dir.replacingOccurrences(of: "~", with: "."), item.container) {
            let folder = URL(fileURLWithPath: Paths.mobileDocuments).appendingPathComponent(dir)
                .appendingPathComponent(item.folder)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where matchesAbbreviation(name, item.name) {
                let url = folder.appendingPathComponent(name)
                guard let (id, _) = try? await NSFileProviderManager.identifierForUserVisibleFile(at: url)
                else { continue }
                if id.rawValue == item.fileProviderID { return url.resolvingSymlinksInPath().path }
            }
        }
        return nil
    }

    /// The upload or download error iCloud reports for the file, if any.
    static func transferError(_ path: String) -> String? {
        let keys: Set<URLResourceKey> = [.ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey]
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys)
        return (v?.ubiquitousItemUploadingError ?? v?.ubiquitousItemDownloadingError)?.localizedDescription
    }

    /// Seconds without byte progress after which a queued file counts as stuck.
    static let stallTime: TimeInterval = 120

    /// A file in transfer is stuck when it carries an upload or download error, or
    /// when iCloud's queue lists it and its byte count has not changed for `stallTime`.
    static func isStuck(hasError: Bool, isQueued: Bool, unchangedFor: TimeInterval) -> Bool {
        hasError || (isQueued && unchangedFor >= stallTime)
    }

    private static func capture(_ line: String, _ regex: Regex<(Substring, Substring)>) -> String? {
        line.firstMatch(of: regex).map { String($0.1) }
    }
}

/// Watch for Stuck Files: while it is on, reads iCloud Drive's queue with
/// `brctl status` at once and then every minute. Queued files that SyncGlass did
/// not see change go to the tracker; files in transfer that make no progress are
/// marked stuck. `brctl status` shows the queue as it is when it runs, so turning
/// the watch on after a transfer got stuck still finds the file.
@MainActor
@Observable
final class ICloudQueueMonitor {
    static let shared = ICloudQueueMonitor()

    /// Off at launch.
    private(set) var isWatching = false

    /// Queue items by path, from the last run.
    private(set) var items: [String: QueueItem] = [:]
    /// Paths in transfer that are stuck (`ICloudQueue.isStuck`).
    private(set) var stuck: Set<String> = []
    /// Upload or download errors of the paths in transfer.
    private(set) var errors: [String: String] = [:]

    /// File Provider identifier → path, so each item is resolved once.
    @ObservationIgnored private var resolved: [String: String] = [:]
    /// Byte count of each path in transfer, and since when it has not changed.
    @ObservationIgnored private var lastBytes: [String: (bytes: Int64?, since: Date)] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(progress: FileProgressMonitor) {
        task?.cancel()
        isWatching = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.update(progress: progress)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isWatching = false
        items = [:]
        stuck = []
        errors = [:]
        lastBytes = [:]
    }

    private func update(progress: FileProgressMonitor) async {
        let output = await Task.detached(priority: .utility) { ICloudQueue.readStatus() }.value
        guard isWatching else { return }
        let now = Date()
        var byPath: [String: QueueItem] = [:]
        for item in ICloudQueue.parse(output ?? "", now: now) {
            var path = resolved[item.fileProviderID].flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            if path == nil { path = await ICloudQueue.resolve(item) }
            guard let path else { continue }
            resolved[item.fileProviderID] = path
            byPath[path] = item
        }
        items = byPath

        guard let tracker = Tracker.shared else { return }
        let snapshot = tracker.snapshot()
        tracker.queuePaths(byPath.keys.filter { !snapshot.totalTransfers.contains($0) })

        let inFlight = Set(snapshot.totalTransfers).subtracting(snapshot.completedTransfers)
        let bytes = progress.progressByPath()
        var stuckNow = Set<String>()
        var errorsNow: [String: String] = [:]
        for path in inFlight {
            let current = bytes[path]?.completedBytes
            let since = lastBytes[path].flatMap { $0.bytes == current ? $0.since : nil } ?? now
            lastBytes[path] = (current, since)
            errorsNow[path] = ICloudQueue.transferError(path)
            if ICloudQueue.isStuck(hasError: errorsNow[path] != nil, isQueued: byPath[path] != nil,
                                   unchangedFor: now.timeIntervalSince(since)) {
                stuckNow.insert(path)
            }
        }
        lastBytes = lastBytes.filter { inFlight.contains($0.key) }
        stuck = stuckNow
        errors = errorsNow
    }
}

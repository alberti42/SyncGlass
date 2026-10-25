import CoreServices
import Foundation

/// What the UI needs after a status change, copied under the tracker's lock.
struct TrackerSnapshot {
    enum Status: Int {
        case idle = 0
        /// Files are being uploaded or downloaded.
        case transferring = 1
        /// Changes from other devices arrived and nothing is in flight.
        case syncing = 2
    }

    var status: Status = .idle
    var transferCount = 0
    var completedTransferCount = 0
    var totalTransferCount = 0
    var completedDownloadCount = 0
    var previousCompletedDownloadCount = 0
    var elapsedTransferTime: Double = 0
    var isFinishedTransferring = false
    var totalTransfers: [String] = []
    var completedTransfers: Set<String> = []
    /// Paths in flight that are being downloaded rather than uploaded.
    var downloadingTransfers: Set<String> = []
    var recentTransfers: [RecentTransfer] = []

    /// True when every path in flight is a download.
    var isDownloadingOnly: Bool { transferCount > 0 && downloadingTransfers.count == transferCount }

    var progress: Double {
        guard totalTransferCount > 0 else { return 0 }
        return min(1, max(0, Double(completedTransferCount) / Double(totalTransferCount)))
    }
}

@MainActor
protocol TrackerDelegate: AnyObject {
    func trackerStatusChanged(_ snapshot: TrackerSnapshot)
}

/// Watches the iCloud folder and keeps the set of paths in transfer.
///
/// An FSEvents stream queues every changed path. A background thread checks the
/// queued paths and re-checks the paths in flight, a batch at a time, then sleeps.
/// The sleep grows by 0.25 s per pass without progress, capped by the number of
/// paths in flight (10, 20, 30 or 60 s).
final class Tracker: @unchecked Sendable {
    nonisolated(unsafe) private(set) static var shared: Tracker!

    @MainActor weak var delegate: TrackerDelegate?

    private let queueLock = NSLock()   // guards `pending`
    private let stateLock = NSLock()   // guards the transfer sets and the counters

    /// Paths waiting for a first check (FSEvents output).
    private var pending = Set<String>()
    /// Paths that arrived while the poll thread held `queueLock`.
    private var overflow: [String] = []
    /// Paths in flight.
    private var transfers = Set<String>()
    /// Paths in flight whose last check reported a download.
    private var downloading = Set<String>()
    /// Paths in flight that were checked during the current round-robin cycle.
    private var checkedRecently = Set<String>()
    /// Paths that finished transferring during this session.
    private var completed = Set<String>()
    /// Every path that was in flight during this session.
    private var total = Set<String>()
    /// Uploaded paths that changed without being in flight: changes from other devices.
    private var downloads = Set<String>()
    private var recents: [RecentTransfer]

    private var startTime: CFAbsoluteTime = 0
    private var lastDownloadTime: CFAbsoluteTime = 0
    private var elapsedTransferTime: Double = 0
    private var sleepInterval: Double = 1
    private var batchSize = 25
    private var previousTransferCount = 0
    private var previousDownloadCount = 0
    private var completedThisPass = 0
    private var finished = false
    private var logDirty = false

    private var paused = false
    private var thread: Thread?
    private var stream: FSEventStreamRef?
    private let streamQueue = DispatchQueue(label: "SyncGlass.fsevents")

    private(set) var directory: String
    private let log = HistoryLog()

    init(directory: String) {
        self.directory = directory
        recents = RecentTransfersStore.load()
        cleanRecentTransfers()
        resetInactivityTimer()
        Tracker.shared = self

        let t = Thread { [weak self] in self?.pollForStatus() }
        t.name = "SyncGlass.tracker"
        t.qualityOfService = .utility
        thread = t
        t.start()
    }

    // MARK: Control

    func setDirectory(_ path: String) {
        directory = NSString(string: path).expandingTildeInPath
        if stream != nil { start() }
    }

    /// `START`: watch the folder plus Desktop and Documents when they are in iCloud.
    func start() {
        var paths = [directory]
        for dir in [FileManager.SearchPathDirectory.documentDirectory, .desktopDirectory] {
            if let p = NSSearchPathForDirectoriesInDomains(dir, .userDomainMask, true).last,
               PathChecks.isTracked(p) {
                paths.append(p)
            }
        }
        monitorDirectories(paths)
    }

    func pause() { withState { paused = true } }

    func resume() { withState { paused = false } }

    func networkReachabilityChanged(isReachable: Bool) {
        if isReachable {
            resetInactivityTimer()
            resume()
        } else {
            pause()
        }
    }

    /// Results of a rescan replace the paths in flight.
    func setExistingTransfers(_ paths: [String]) {
        withState {
            startTime = CFAbsoluteTimeGetCurrent()
            transfers = Set(paths)
            total = Set(paths)
            downloading.removeAll()
        }
    }

    /// Queue paths that FSEvents did not report, such as the items in iCloud's
    /// queue. They go through the same checks as changed paths.
    func queuePaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        streamQueue.async { [weak self] in paths.forEach { self?.queueFile($0) } }
    }

    /// Stop Tracking in the transfer list moves the path to completed.
    func removeTransfers(_ paths: [String]) {
        withState {
            for path in paths where FileManager.default.fileExists(atPath: path) && transfers.contains(path) {
                transfers.remove(path)
                downloading.remove(path)
                completed.insert(path)
            }
        }
    }

    func snapshot() -> TrackerSnapshot {
        withState { makeSnapshot() }
    }

    /// Drop recent paths that no longer exist.
    func cleanRecentTransfers() {
        withState { recents.removeAll { !FileManager.default.fileExists(atPath: $0.path) } }
    }

    func clearHistory() {
        log.clear()
        withState { recents.removeAll() }
        RecentTransfersStore.save([])
    }

    // MARK: FSEvents

    private func monitorDirectories(_ paths: [String]) {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let tracker = Unmanaged<Tracker>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            for path in paths.prefix(count) { tracker.queueFile(path) }
        }
        // UseCFTypes | NoDefer | WatchRoot | IgnoreSelf | FileEvents, latency 1 s.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf
                | kFSEventStreamCreateFlagFileEvents)
        guard let s = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        else {
            NSLog("SyncGlass: FSEventStreamCreate returned nil")
            return
        }
        FSEventStreamSetDispatchQueue(s, streamQueue)
        FSEventStreamStart(s)
        stream = s
    }

    /// Queue a changed path. Runs on `streamQueue`.
    private func queueFile(_ path: String) {
        if queueLock.try() {
            pending.insert(path)
            queueLock.unlock()
        } else {
            overflow.append(path)
            streamQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.mergePendingQueue() }
        }
    }

    /// Move paths that arrived while the poll thread held `queueLock`. Runs on `streamQueue`.
    private func mergePendingQueue() {
        guard !overflow.isEmpty else { return }
        if queueLock.try() {
            pending.formUnion(overflow)
            overflow.removeAll()
            queueLock.unlock()
        } else {
            streamQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.mergePendingQueue() }
        }
    }

    // MARK: Poll loop

    private var isPaused: Bool { withState { paused } }

    /// Restart the sleep at 1 s and read the batch size from the settings.
    private func resetInactivityTimer() {
        sleepInterval = 1
        batchSize = Prefs.pollingMode.batchSize
    }

    /// The poll thread's loop.
    private func pollForStatus() {
        while !(thread?.isCancelled ?? true) {
            while isPaused { Thread.sleep(forTimeInterval: 5) }

            withState {
                completedThisPass = 0
                if finished {
                    finished = false
                    startTime = 0
                    lastDownloadTime = 0
                    completed.removeAll()
                    total.removeAll()
                    downloads.removeAll()
                }
            }

            checkPendingPaths()
            if isPaused { continue }
            recheckTransfers()
            updateTransferStatus()

            if logDirty {
                log.truncateIfLarger(thanMB: Prefs.clearLogAfterSize)
                logDirty = false
            }

            let inFlight = withState { transfers.count }
            if completedThisPass == 0 && inFlight > 0 {
                let cap: Double
                switch inFlight {
                case 1...10: cap = 10
                case 11...50: cap = 20
                case 51...100: cap = 30
                default: cap = 60
                }
                sleepInterval = min(sleepInterval + 0.25, cap)
            }
            Thread.sleep(forTimeInterval: sleepInterval)
        }
    }

    private func checkPendingPaths() {
        queueLock.lock()
        defer { queueLock.unlock() }
        guard !pending.isEmpty else { return }

        resetInactivityTimer()
        var lastBreath = CFAbsoluteTimeGetCurrent()
        let trackDownloads = Prefs.trackIncomingDownloads
        for path in pending {
            if isPaused { break }
            pending.remove(path)
            if path.hasSuffix(".DS_Store") { continue }
            let state = ItemState(path: path)
            if Prefs.ignoreHiddenFiles && state.isHidden && !(trackDownloads && state.isDownloading) { continue }
            if Prefs.ignoreSymbolicLinks && state.isSymbolicLink { continue }
            if !PathChecks.isInsidePackage(path) && state.containsBytes && (!state.isDirectory || state.isPackage) {
                checkStatus(path, state: state)
            }
            if CFAbsoluteTimeGetCurrent() - lastBreath > 1 {
                Thread.sleep(forTimeInterval: 0.5)
                lastBreath = CFAbsoluteTimeGetCurrent()
            }
        }
    }

    /// Re-check up to `batchSize` paths in flight, round-robin.
    private func recheckTransfers() {
        let batch: [String] = withState {
            guard !transfers.isEmpty else { return [] }
            var picked = transfers.subtracting(checkedRecently).prefix(batchSize).map { $0 }
            if picked.isEmpty {
                checkedRecently.removeAll()
                picked = Array(transfers.prefix(batchSize))
            }
            checkedRecently.formUnion(picked)
            return picked
        }
        for path in batch {
            if isPaused { return }
            checkStatus(path, state: ItemState(path: path))
        }
    }

    /// Check one path: start tracking it if it is in transfer, record it as
    /// finished if it was tracked and is now current, or count it as a change
    /// from another device. A download in flight is read from
    /// `ubiquitousItemIsDownloading`; macOS 14 and later keep dataless files in
    /// place and create no `.icloud` placeholder files. A path that is not in
    /// iCloud, such as one inside a `.nosync` folder, has no upload state and is
    /// dropped like a path that no longer exists.
    private func checkStatus(_ path: String, state: ItemState) {
        let trackDownloads = Prefs.trackIncomingDownloads
        let phase = state.phase(trackDownloads: trackDownloads)

        guard phase != .ignored else {
            withState {
                transfers.remove(path)
                downloading.remove(path)
            }
            resetInactivityTimer()
            return
        }

        let tracked = withState { transfers.contains(path) }

        if case .inFlight(let isDownload) = phase {
            if tracked || PathChecks.passesFilters(path) {
                withState {
                    if startTime == 0 { startTime = CFAbsoluteTimeGetCurrent() }
                    transfers.insert(path)
                    total.insert(path)
                    if isDownload {
                        downloading.insert(path)
                    } else {
                        downloading.remove(path)
                    }
                }
            }
        } else if tracked {
            let wasDownloading = withState { downloading.contains(path) }
            addTransferFinishedEntry(path, kind: wasDownloading ? .download : .upload)
            withState {
                transfers.remove(path)
                downloading.remove(path)
                completedThisPass += 1
                completed.insert(path)
            }
        } else if trackDownloads && PathChecks.passesFilters(path) {
            let isNew = withState { () -> Bool in
                guard !downloads.contains(path) else { return false }
                if startTime == 0 { startTime = CFAbsoluteTimeGetCurrent() }
                lastDownloadTime = CFAbsoluteTimeGetCurrent()
                downloads.insert(path)
                return true
            }
            if isNew && Prefs.downloadErrorLogging { addTransferFinishedEntry(path, kind: .change) }
        }
        resetInactivityTimer()
    }

    /// Notice when a batch of transfers ends, log it and notify the delegate.
    private func updateTransferStatus() {
        let (count, downloadCount) = withState { (transfers.count, downloads.count) }

        if count != previousTransferCount && count != 0 {
            notify()
        } else if previousTransferCount > 0 && count == 0 {
            let snapshotCompleted = withState { () -> Int in
                finished = true
                elapsedTransferTime = CFAbsoluteTimeGetCurrent() - startTime
                return completed.count
            }
            if Prefs.enableLogging && snapshotCompleted > 0 {
                let noun = snapshotCompleted == 1 ? "file was" : "files were"
                writeLog("[\(HistoryLog.timestamp())] ======== \(snapshotCompleted) \(noun) transferred ========")
            }
            RecentTransfersStore.save(withState { recents })
            Prefs.store.set(Date(), forKey: PrefKey.lastTransferDate)
            notify()
        } else if downloadCount != 0 && count == 0 {
            if downloadCount != previousDownloadCount { notify() }
            let quiet = CFAbsoluteTimeGetCurrent() - withState { lastDownloadTime }
            if quiet > Prefs.downloadBatchDelay {
                if Prefs.downloadErrorLogging {
                    let noun = downloadCount == 1 ? "file was" : "files were"
                    writeLog("[\(HistoryLog.timestamp())] ======== \(downloadCount) \(noun) downloaded ========")
                }
                RecentTransfersStore.save(withState { recents })
                withState {
                    elapsedTransferTime = 0
                    previousDownloadCount = downloads.count
                    downloads.removeAll()
                    finished = true
                }
                notify()
            }
        }

        withState {
            previousTransferCount = transfers.count
            if !finished { previousDownloadCount = downloads.count }
        }
    }

    // MARK: History

    /// Add a finished transfer to recents with the time and direction,
    /// and write a log line relative to the folder.
    private func addTransferFinishedEntry(_ path: String, kind: RecentTransfer.Kind) {
        withState {
            recents.removeAll { $0.path == path }
            recents.insert(RecentTransfer(path: path, date: Date(), kind: kind), at: 0)
            if recents.count > Prefs.recentFilesLimit { recents.removeLast(recents.count - Prefs.recentFilesLimit) }
        }
        guard Prefs.enableLogging else { return }
        let shown = path.hasPrefix(directory) ? String(path.dropFirst(directory.count)) : (path as NSString).abbreviatingWithTildeInPath
        writeLog("[\(HistoryLog.timestamp())] \(shown)")
    }

    private func writeLog(_ line: String) {
        log.append(line)
        logDirty = true
    }

    // MARK: Helpers

    @discardableResult
    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    /// Call with `stateLock` held.
    private func makeSnapshot() -> TrackerSnapshot {
        var s = TrackerSnapshot()
        s.status = !transfers.isEmpty ? .transferring : (!downloads.isEmpty ? .syncing : .idle)
        s.transferCount = transfers.count
        s.completedTransferCount = completed.count
        s.totalTransferCount = total.count
        s.completedDownloadCount = downloads.count
        s.previousCompletedDownloadCount = previousDownloadCount
        s.elapsedTransferTime = elapsedTransferTime
        s.isFinishedTransferring = finished
        s.totalTransfers = Array(total)
        s.completedTransfers = completed
        s.downloadingTransfers = downloading.intersection(transfers)
        s.recentTransfers = recents
        return s
    }

    private func notify() {
        let s = snapshot()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.delegate?.trackerStatusChanged(s) }
        }
    }
}

/// The history log file.
final class HistoryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func timestamp() -> String { formatter.string(from: Date()) }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = Paths.historyLog
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    func truncateIfLarger(thanMB limit: Int) {
        let size = (try? FileManager.default.attributesOfItem(atPath: Paths.historyLog.path)[.size] as? Int) ?? 0
        if limit > 0 && size >> 20 >= limit { clear() }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.truncate(atOffset: 0)
        if handle == nil { try? Data().write(to: Paths.historyLog) }
    }
}

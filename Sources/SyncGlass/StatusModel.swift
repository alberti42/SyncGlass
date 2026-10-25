import AppKit
import Observation

/// State shared by the menu-bar icon and the panel.
@MainActor
@Observable
final class StatusModel {
    enum Tab: Hashable { case transfers, recent }

    private(set) var snapshot = TrackerSnapshot()
    private(set) var isReachable = true
    var tab: Tab = .recent
    private(set) var diskUsage: String? = Prefs.store.string(forKey: PrefKey.iCloudDiskUsage)
    private(set) var showsProgressInMenuBar = Prefs.statusItemMode == .progressWheel

    /// Byte progress of the files in transfer, keyed by path.
    private(set) var fileProgress: [String: FileProgress] = [:]
    @ObservationIgnored var fileProgressMonitor: FileProgressMonitor?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    @ObservationIgnored private var hadTransfers = false
    /// Set by the debug preview so sample data is not replaced on appear.
    @ObservationIgnored var isPreview = false
    @ObservationIgnored private var diskUsageTask: Task<Void, Never>?

    var menuBarImage: NSImage {
        MenuBarIcon.image(for: snapshot, isReachable: isReachable, showsProgress: showsProgressInMenuBar)
    }

    /// Switch to Transfers when transfers start and back to Recent when they end.
    func update(_ snapshot: TrackerSnapshot) {
        self.snapshot = snapshot
        let hasTransfers = snapshot.transferCount > 0
        if hasTransfers != hadTransfers { tab = hasTransfers ? .transfers : .recent }
        hadTransfers = hasTransfers
    }

    func setReachable(_ reachable: Bool) { isReachable = reachable }

    func preferencesChanged() {
        showsProgressInMenuBar = Prefs.statusItemMode == .progressWheel
    }

    func folderChanged() {
        Prefs.store.removeObject(forKey: PrefKey.iCloudDiskUsage)
        diskUsage = nil
    }

    /// Called when the panel opens.
    func refresh() {
        guard !isPreview, let tracker = Tracker.shared else { return }
        tracker.cleanRecentTransfers()
        update(tracker.snapshot())
        updateDiskUsage()
    }

    // MARK: Per-file progress

    func progress(for path: String) -> FileProgress? {
        fileProgress[path]
    }

    /// Read per-file progress twice a second while the panel is open.
    func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let latest = self.fileProgressMonitor?.progressByPath() ?? [:]
                if latest != self.fileProgress { self.fileProgress = latest }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    // MARK: Stuck files

    var isWatchingForStuckFiles: Bool { ICloudQueueMonitor.shared.isWatching }

    func toggleStuckFileWatch() {
        let monitor = ICloudQueueMonitor.shared
        if monitor.isWatching {
            monitor.stop()
        } else if let fileProgressMonitor {
            monitor.start(progress: fileProgressMonitor)
        }
    }

    func isStuck(_ path: String) -> Bool { ICloudQueueMonitor.shared.stuck.contains(path) }

    var stuckCount: Int { ICloudQueueMonitor.shared.stuck.count }

    var lastStuckFileCheck: Date? { ICloudQueueMonitor.shared.lastCheck }

    func queueItem(for path: String) -> QueueItem? { ICloudQueueMonitor.shared.items[path] }

    func transferError(for path: String) -> String? { ICloudQueueMonitor.shared.errors[path] }

    // MARK: Lists

    var transfers: [String] {
        guard !snapshot.isFinishedTransferring else { return [] }
        // Sort by name without extension, in Finder order.
        return snapshot.totalTransfers.sorted {
            let a = (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
            let b = (($1 as NSString).lastPathComponent as NSString).deletingPathExtension
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    var recents: [RecentTransfer] {
        snapshot.recentTransfers.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Text

    var title: String {
        guard isReachable else { return "Offline" }
        switch snapshot.status {
        case .idle: return "Up to Date"
        case .syncing: return "Syncing"
        case .transferring: return snapshot.isDownloadingOnly ? "Downloading" : "Uploading"
        }
    }

    var detail: String {
        guard isReachable else { return "Transfers resume when the network is back." }
        return Self.detailText(for: snapshot)
    }

    static func detailText(for s: TrackerSnapshot) -> String {
        switch s.status {
        case .syncing:
            return s.completedDownloadCount == 1
                ? "Syncing changes to 1 file…"
                : "Syncing changes to \(s.completedDownloadCount) files…"
        case .transferring:
            let noun = s.transferCount == 1 ? "file" : "files"
            return "\(s.transferCount) \(noun) in progress"
        case .idle:
            if let last = Prefs.store.object(forKey: PrefKey.lastTransferDate) as? Date {
                let f = RelativeDateTimeFormatter()
                f.dateTimeStyle = .named   // "now", "yesterday"
                f.unitsStyle = .full
                return "Last transfer \(f.localizedString(for: min(last, Date()), relativeTo: Date()))"
            }
            return "No files are being transferred."
        }
    }

    var progressText: String {
        "\(snapshot.completedTransferCount) of \(snapshot.totalTransferCount) complete"
    }

    // MARK: Disk usage

    /// `updateICloudDiskUsage`: runs `du -sh` on the folder and keeps the first column.
    func updateDiskUsage() {
        diskUsageTask?.cancel()
        let folder = Prefs.folder
        diskUsageTask = Task { [weak self] in
            let size = await Task.detached(priority: .utility) { () -> String? in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                p.arguments = ["-sh", folder]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                return String(decoding: data, as: UTF8.self)
                    .split(whereSeparator: \.isWhitespace).first.map(String.init)
            }.value
            guard let size, !Task.isCancelled else { return }
            // du prints "12G"; show "12 GB".
            let shown = size.dropLast() + " " + String(size.last ?? "B") + (size.last == "B" ? "" : "B")
            Prefs.store.set(shown, forKey: PrefKey.iCloudDiskUsage)
            self?.diskUsage = shown
        }
    }

    // MARK: Actions

    func reveal(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    /// Stop Tracking: the file keeps syncing but is no longer tracked.
    func ignore(_ path: String) {
        Tracker.shared.removeTransfers([path])
        update(Tracker.shared.snapshot())
    }

    /// Opens System Settings > [Apple Account] > iCloud. The scene follows `?`;
    /// with `:` System Settings opens without selecting a page.
    func openICloudSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?icloud") {
            NSWorkspace.shared.open(url)
        }
    }

    func openICloudDrive() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.iCloudDrive))
    }

    func openICloudOnline() {
        NSWorkspace.shared.open(URL(string: "https://www.icloud.com/iclouddrive")!)
    }

    func openLog() {
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open([Paths.historyLog], withApplicationAt: console,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear the transfer history?"
        alert.informativeText = "The history log and the list of recent files are deleted. This cannot be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Tracker.shared.clearHistory()
        update(Tracker.shared.snapshot())
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

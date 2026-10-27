import AppKit
import SwiftUI

/// The window shown from the menu-bar icon, with the Transfers and Recent lists.
struct StatusPanel: View {
    @Bindable var model: StatusModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            header
            if model.snapshot.status == .transferring && model.snapshot.totalTransferCount > 0 {
                progress
            }
            if model.isWatchingForStuckFiles {
                WatchBar(model: model)
            }
            Picker("View", selection: $model.tab) {
                Text("Transfers").tag(StatusModel.Tab.transfers)
                Text("Recent").tag(StatusModel.Tab.recent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch model.tab {
                case .transfers: TransferList(model: model)
                case .recent: RecentList(model: model)
                }
            }
            .frame(height: 300)

            footer
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            model.refresh()
            model.startProgressUpdates()
        }
        .onDisappear { model.stopProgressUpdates() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(model: model)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline)
                // Refresh "Last transfer 3 minutes ago" while the panel stays open.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(model.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            moreMenu
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: model.snapshot.progress)
                .progressViewStyle(.linear)
            Text(model.progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// A glass button that opens a native menu. SwiftUI's `Menu` ignores
    /// `.buttonStyle(.glass)` and the label frame, which left bare, small dots.
    private var moreMenu: some View {
        MoreButton { anchor in
            let menu = NSMenu()
            menu.addItem(ActionMenuItem("Scan for Transfers…", systemImage: "magnifyingglass") {
                Scanner.scanConfiguredFolder()
            })
            let watch = ActionMenuItem("Watch for Stuck Files", systemImage: "exclamationmark.triangle") {
                model.toggleStuckFileWatch()
            }
            watch.state = model.isWatchingForStuckFiles ? .on : .off
            menu.addItem(watch)
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Open History Log", systemImage: "doc.text") { model.openLog() })
            menu.addItem(ActionMenuItem("Clear History…", systemImage: "trash") { model.clearHistory() })
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Settings…", systemImage: "gearshape", key: ",") {
                NSApp.activate()
                openSettings()
            })
            menu.addItem(ActionMenuItem("About SyncGlass", systemImage: "info.circle") { model.showAbout() })
            if Updater.shared.isAvailable {
                let title = Updater.shared.pendingVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
                menu.addItem(ActionMenuItem(title, systemImage: "arrow.down.circle") {
                    Updater.shared.checkForUpdates()
                })
            }
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Quit SyncGlass", systemImage: "power", key: "q") {
                NSApp.terminate(nil)
            })
            // Open the menu below the button, right edges aligned.
            let y = anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4
            let x = anchor.bounds.maxX - menu.size.width
            menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: anchor)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Label(model.diskUsage.map { "\($0) on this Mac" } ?? "Calculating size…", systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    FooterButton(title: "Open iCloud Drive", systemImage: "folder") { model.openICloudDrive() }
                    FooterButton(title: "Open iCloud.com", systemImage: "safari") { model.openICloudOnline() }
                    FooterButton(title: "iCloud Settings", systemImage: "icloud") { model.openICloudSettings() }
                    FooterButton(title: "SyncGlass Settings", systemImage: "gearshape") {
                        NSApp.activate()
                        openSettings()
                    }
                }
            }
        }
    }
}

private struct MoreButton: View {
    let showMenu: (NSView) -> Void
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            if let view = anchor.view { showMenu(view) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .background(MenuAnchorView(anchor: anchor))
        .help("More")
        .accessibilityLabel("More")
    }
}

/// Holds the AppKit view behind `MoreButton`, which `NSMenu.popUp` needs for positioning.
@MainActor
private final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// An `NSMenuItem` that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, systemImage: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The colored status symbol at the top of the panel. Only the menu-bar icon
/// must stay monochrome; inside the panel the state can use color.
private struct StatusBadge: View {
    let model: StatusModel

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: isActive)
            .frame(width: 40, height: 40)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .circle)
            .accessibilityHidden(true)
    }

    private var isActive: Bool { model.isReachable && model.snapshot.status != .idle }

    private var symbol: String {
        if !model.isReachable { return "icloud.slash" }
        switch model.snapshot.status {
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.clockwise.icloud"
        case .transferring: return model.snapshot.isDownloadingOnly ? "icloud.and.arrow.down" : "icloud.and.arrow.up"
        }
    }

    private var tint: Color {
        if !model.isReachable { return .secondary }
        switch model.snapshot.status {
        case .idle: return .green
        case .syncing: return .teal
        case .transferring: return .accentColor
        }
    }
}

/// Shown while Watch for Stuck Files is on: when SyncGlass last read iCloud's
/// queue and how many files are stuck. The ⋯ menu turns the watch off.
private struct WatchBar: View {
    let model: StatusModel
    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Watching for stuck files").font(.callout.weight(.medium))
                // Refresh "Checked 20 sec. ago" while the panel stays open.
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Text(detail(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            Button {
                showsInfo.toggle()
            } label: {
                Image(systemName: "info")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("About Watch for Stuck Files")
            .accessibilityLabel("About Watch for Stuck Files")
            .popover(isPresented: $showsInfo, arrowEdge: .bottom) { info }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 12))
    }

    private var info: some View {
        let minutes = Int(ICloudQueue.stallTime / 60)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Watching for stuck files").font(.headline)
            Text("Turn this on when you have reason to believe that iCloud Drive is stuck on a file, and off once you know which file it is.")
            Text("SyncGlass reads iCloud Drive's queue at once and then every minute.")
            Text("A file is marked stuck when iCloud reports an upload or download error for it, or when it is in iCloud's queue and its upload has not progressed for \(minutes) minutes. So a file without an error appears as stuck only after \(minutes) minutes of watching.")
            Text("If a file stays stuck, we would like to hear from you. SyncGlass shows which file is stuck, but it names the cause only when iCloud reports an error for the file, as it does when the network connection is missing. Please open an issue on GitHub with the output of brctl status: real cases help us diagnose more kinds of problems.")
            Link("How to send it", destination: URL(string: "https://github.com/alberti42/SyncGlass#troubleshooting")!)
            Text("Choose Watch for Stuck Files in the ⋯ menu again to stop.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding(16)
    }

    /// "Checked 20 sec. ago · none stuck", with "so far" while the watch has run
    /// for less than `ICloudQueue.stallTime`.
    private func detail(now: Date) -> String {
        guard let last = model.lastStuckFileCheck else { return "Checking…" }
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named   // "now"
        f.unitsStyle = .short
        let n = model.stuckCount
        let early = model.stuckFileWatchStart.map { now.timeIntervalSince($0) < ICloudQueue.stallTime } ?? false
        let found = n == 0 ? (early ? "none stuck so far" : "none stuck") : "\(n) stuck"
        return "Checked \(f.localizedString(for: min(last, now), relativeTo: now)) · \(found)"
    }
}

// MARK: Lists

private struct TransferList: View {
    let model: StatusModel

    var body: some View {
        let paths = model.transfers
        if paths.isEmpty {
            ContentUnavailableView("No Transfers", systemImage: "checkmark.icloud",
                                   description: Text("Files that are uploading or downloading appear here."))
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(paths, id: \.self) { path in
                        TransferRow(
                            path: path,
                            isComplete: model.snapshot.completedTransfers.contains(path),
                            isDownloading: model.snapshot.downloadingTransfers.contains(path),
                            progress: model.progress(for: path),
                            isStuck: model.isStuck(path),
                            lastAttempt: model.queueItem(for: path)?.operation?.lastAttempt,
                            error: model.transferError(for: path),
                            model: model)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
    }
}

private struct RecentList: View {
    let model: StatusModel

    var body: some View {
        let entries = model.recents
        if entries.isEmpty {
            ContentUnavailableView("No Recent Transfers", systemImage: "clock",
                                   description: Text("Files appear here after they finish transferring."))
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries, id: \.path) { entry in
                        RecentRow(entry: entry, model: model)
                    }
                }
            }
        }
    }
}

/// A file in transfer: icon, name, direction and size, with Stop Tracking,
/// Get Info and Show in Finder on hover.
private struct TransferRow: View {
    let path: String
    let isComplete: Bool
    let isDownloading: Bool
    /// Byte progress from `FileProgressMonitor`; nil when iCloud has not published any.
    let progress: FileProgress?
    /// From Watch for Stuck Files (`ICloudQueueMonitor`).
    let isStuck: Bool
    let lastAttempt: Date?
    let error: String?
    let model: StatusModel
    @State private var hovering = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        FileRow(path: path, hovering: hovering) {
            // Refresh "last attempt 4 min ago" while the panel stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(stuckNow ? stuckDetail(now: context.date) : detail).monospacedDigit()
            }
        } trailing: {
            if hovering {
                HStack(spacing: 4) {
                    if !isComplete {
                        RowButton(title: "Stop Tracking", systemImage: "xmark") { model.ignore(path) }
                    }
                    RowButton(title: "Get Info", systemImage: "info") { FileInfo.open(path, with: openWindow) }
                    RowButton(title: "Show in Finder", systemImage: "magnifyingglass") { model.reveal(path) }
                }
            } else if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Complete")
            } else if stuckNow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error ?? "No progress for \(Int(ICloudQueue.stallTime / 60)) minutes")
                    .accessibilityLabel("Stuck")
            } else if let progress {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityLabel("\(downloading ? "Downloading" : "Uploading") \(percent(progress))")
            } else {
                Image(systemName: isDownloading ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityLabel(isDownloading ? "Downloading" : "Uploading")
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.reveal(path) }
    }

    /// The direction iCloud reports in the progress object wins over the tracker's guess.
    private var downloading: Bool {
        switch progress?.direction {
        case .downloading?: return true
        case .uploading?: return false
        case nil: return isDownloading
        }
    }

    private var stuckNow: Bool { isStuck && !isComplete }

    /// "Waiting · last attempt 4 min ago"
    private func stuckDetail(now: Date) -> String {
        guard let lastAttempt else { return "Waiting" }
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named   // "now", "yesterday"
        f.unitsStyle = .short
        return "Waiting · last attempt \(f.localizedString(for: min(lastAttempt, now), relativeTo: now))"
    }

    private func percent(_ p: FileProgress) -> String {
        p.fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private var detail: String {
        let state = isComplete ? "Done" : (downloading ? "Downloading" : "Uploading")
        if !isComplete, let progress, progress.totalBytes > 0 {
            let total = PathChecks.humanReadable(bytes: Double(progress.totalBytes))
            return "\(state) · \(percent(progress)) of \(total)"
        }
        guard FileManager.default.fileExists(atPath: path) else { return state }
        let item = ItemState(path: path)
        let bytes = item.isPackage ? PathChecks.directorySize(path) : item.fileSize
        return "\(state) · \(PathChecks.humanReadable(bytes: Double(bytes)))"
    }
}

/// A recently transferred file: icon, name, and when and how the transfer finished.
private struct RecentRow: View {
    let entry: RecentTransfer
    let model: StatusModel
    @State private var hovering = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        FileRow(path: entry.path, hovering: hovering) {
            // Refresh "3 min ago" while the panel stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(detail(now: context.date))
            }
        } trailing: {
            if hovering {
                HStack(spacing: 4) {
                    RowButton(title: "Get Info", systemImage: "info") { FileInfo.open(entry.path, with: openWindow) }
                    RowButton(title: "Show in Finder", systemImage: "magnifyingglass") { model.reveal(entry.path) }
                }
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.reveal(entry.path) }
    }

    private func detail(now: Date) -> String {
        let folder = ((entry.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let location = folder == "com~apple~CloudDocs" ? "iCloud Drive" : folder
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named   // "now", "yesterday"
        f.unitsStyle = .short
        return "\(location) · \(entry.kind.verb) \(f.localizedString(for: min(entry.date, now), relativeTo: now))"
    }
}

private struct FileRow<Detail: View, Trailing: View>: View {
    let path: String
    let hovering: Bool
    @ViewBuilder let detail: Detail
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(FileManager.default.displayName(atPath: path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .help((path as NSString).abbreviatingWithTildeInPath)
    }
}

private struct RowButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}

import AppKit
import SwiftUI

/// The "File Info" window: everything macOS exposes about one iCloud file, plus
/// what SyncGlass recorded about its transfers.
enum FileInfo {
    static let windowID = "file-info"

    @MainActor
    static func open(_ path: String, with openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: windowID, value: path)
    }
}

/// One reading of a file's metadata. Dates and iCloud state come from URL
/// resource values; the last-opened date comes from Spotlight.
struct FileDetails {
    var exists = false
    var name = ""
    var kind: String?
    var size: Int?
    var allocatedSize: Int?

    var created: Date?
    var addedToFolder: Date?
    var modified: Date?
    var attributesChanged: Date?
    var lastRead: Date?
    var lastOpened: Date?

    var isUbiquitous = false
    var isUploaded = false
    var isUploading = false
    var isDownloading = false
    var downloadingStatus: URLUbiquitousItemDownloadingStatus?
    var hasConflicts = false
    var isExcludedFromSync = false
    var container: String?
    var uploadError: String?
    var downloadError: String?
    var isShared = false
    var sharedRole: URLUbiquitousSharedItemRole?
    var sharedOwner: String?
    var sharedLastEditor: String?

    private static let keys: Set<URLResourceKey> = [
        .localizedNameKey, .localizedTypeDescriptionKey, .fileSizeKey, .totalFileAllocatedSizeKey,
        .creationDateKey, .addedToDirectoryDateKey, .contentModificationDateKey,
        .attributeModificationDateKey, .contentAccessDateKey,
        .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemIsExcludedFromSyncKey,
        .ubiquitousItemContainerDisplayNameKey, .ubiquitousItemUploadingErrorKey,
        .ubiquitousItemDownloadingErrorKey, .ubiquitousItemIsSharedKey,
        .ubiquitousSharedItemCurrentUserRoleKey, .ubiquitousSharedItemOwnerNameComponentsKey,
        .ubiquitousSharedItemMostRecentEditorNameComponentsKey,
    ]

    init(path: String) {
        name = (path as NSString).lastPathComponent
        exists = FileManager.default.fileExists(atPath: path)
        guard exists else { return }
        var url = URL(fileURLWithPath: path)
        url.removeAllCachedResourceValues()
        guard let v = try? url.resourceValues(forKeys: Self.keys) else { return }

        name = v.localizedName ?? name
        kind = v.localizedTypeDescription
        size = v.fileSize
        allocatedSize = v.totalFileAllocatedSize
        created = v.creationDate
        addedToFolder = v.addedToDirectoryDate
        modified = v.contentModificationDate
        attributesChanged = v.attributeModificationDate
        lastRead = v.contentAccessDate

        isUbiquitous = v.isUbiquitousItem ?? false
        isUploaded = v.ubiquitousItemIsUploaded ?? false
        isUploading = v.ubiquitousItemIsUploading ?? false
        isDownloading = v.ubiquitousItemIsDownloading ?? false
        downloadingStatus = v.ubiquitousItemDownloadingStatus
        hasConflicts = v.ubiquitousItemHasUnresolvedConflicts ?? false
        isExcludedFromSync = v.ubiquitousItemIsExcludedFromSync ?? false
        container = v.ubiquitousItemContainerDisplayName
        uploadError = v.ubiquitousItemUploadingError?.localizedDescription
        downloadError = v.ubiquitousItemDownloadingError?.localizedDescription
        isShared = v.ubiquitousItemIsShared ?? false
        sharedRole = v.ubiquitousSharedItemCurrentUserRole
        let names = PersonNameComponentsFormatter()
        sharedOwner = v.ubiquitousSharedItemOwnerNameComponents.map { names.string(from: $0) }
        sharedLastEditor = v.ubiquitousSharedItemMostRecentEditorNameComponents.map { names.string(from: $0) }

        if let item = MDItemCreate(nil, path as CFString) {
            lastOpened = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
    }

    /// One-line iCloud state, most specific first.
    var statusText: String {
        guard exists else { return "File no longer exists" }
        guard isUbiquitous else { return "Not in iCloud" }
        if isExcludedFromSync { return "Excluded from sync" }
        if isUploading { return "Uploading" }
        if isDownloading { return "Downloading" }
        if !isUploaded { return "Waiting to upload" }
        switch downloadingStatus {
        case .notDownloaded?: return "In iCloud only (not downloaded)"
        case .downloaded?: return "Newer version in iCloud"
        default: return "Up to date"
        }
    }

    var statusSymbol: String {
        guard exists, isUbiquitous else { return "icloud.slash" }
        if isUploading || !isUploaded { return "icloud.and.arrow.up" }
        if isDownloading || downloadingStatus == .downloaded { return "icloud.and.arrow.down" }
        if downloadingStatus == .notDownloaded { return "icloud" }
        return "checkmark.icloud"
    }
}

/// Re-reads the file once a second and subscribes to its transfer progress.
@MainActor
@Observable
final class FileInfoModel {
    let path: String
    private(set) var details: FileDetails
    private(set) var progress: FileProgress?
    private(set) var recorded: RecentTransfer?
    private(set) var isTracked = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let monitor = FileProgressMonitor()

    init(path: String) {
        self.path = path
        details = FileDetails(path: path)
    }

    func start() {
        monitor.track([path])
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        monitor.track([])
    }

    private func reload() {
        details = FileDetails(path: path)
        progress = monitor.progressByPath()[path]
        if let snapshot = Tracker.shared?.snapshot() {
            recorded = snapshot.recentTransfers.first { $0.path == path }
            isTracked = snapshot.totalTransfers.contains(path) && !snapshot.completedTransfers.contains(path)
        }
    }
}

struct FileInfoView: View {
    @State private var model: FileInfoModel

    init(path: String) {
        _model = State(initialValue: FileInfoModel(path: path))
    }

    private var d: FileDetails { model.details }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 18)
            details
        }
        .frame(minWidth: 460, minHeight: 520)
        .navigationTitle(d.name)
        // Proxy icon in the title bar: drag it, or click it for the folder hierarchy.
        .navigationDocument(URL(fileURLWithPath: model.path))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Show in Finder", systemImage: "folder", action: showInFinder)
                    .keyboardShortcut("r")
                    .help("Show in Finder (⌘R)")
                Button("Copy Path", systemImage: "document.on.document", action: copyPath)
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .help("Copy as Pathname (⌥⌘C)")
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var details: some View {
        Form {
            Section("iCloud") {
                LabeledContent("Status") {
                    Label(d.statusText, systemImage: d.statusSymbol)
                }
                LabeledContent("Where") {
                    PathControl(url: URL(fileURLWithPath: model.path))
                }
                if let p = model.progress {
                    LabeledContent(p.direction == .downloading ? "Downloading" : "Uploading") {
                        HStack {
                            ProgressView(value: p.fraction).frame(width: 140)
                            Text("\(p.fraction.formatted(.percent.precision(.fractionLength(0)))) of \(bytes(p.totalBytes))")
                                .monospacedDigit()
                        }
                    }
                }
                if let container = d.container { LabeledContent("Location", value: container) }
                LabeledContent("Conflicts", value: d.hasConflicts ? "Unresolved conflicts" : "None")
                if let e = d.uploadError { LabeledContent("Upload error") { Text(e).foregroundStyle(.red) } }
                if let e = d.downloadError { LabeledContent("Download error") { Text(e).foregroundStyle(.red) } }
                LabeledContent("Shared", value: sharedText)
                if let owner = d.sharedOwner { LabeledContent("Owner", value: owner) }
                if let editor = d.sharedLastEditor { LabeledContent("Last edited by", value: editor) }
            }

            Section {
                LabeledContent("Last transfer") {
                    if let entry = model.recorded {
                        DateText(prefix: entry.kind.verb, date: entry.date)
                    } else {
                        Text("Not in history")
                    }
                }
                LabeledContent("Tracked now", value: model.isTracked ? "Yes, in transfer" : "No")
            } header: {
                Text("SyncGlass")
            }

            Section {
                if let size = d.size { LabeledContent("Size", value: bytes(Int64(size))) }
                if let allocated = d.allocatedSize { LabeledContent("On this Mac", value: bytes(Int64(allocated))) }
                dateRow("Created", d.created)
                dateRow("Added to folder", d.addedToFolder)
                dateRow("Content modified", d.modified)
                dateRow("Attributes changed", d.attributesChanged)
                dateRow("Last opened", d.lastOpened)
                dateRow("Last read", d.lastRead)
            } header: {
                Text("File")
            } footer: {
                Text("macOS records no sync date. \"Attributes changed\" also moves when iCloud updates its own attributes after a transfer, and when tags or permissions change.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Unboxed top area, like Finder's Get Info: icon, name, kind and size.
    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.path))
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
        .contentShape(.rect)
        .contextMenu {
            Button("Show in Finder", systemImage: "folder", action: showInFinder)
            Button("Copy as Pathname", systemImage: "document.on.document", action: copyPath)
        }
    }

    /// "LaunchBar Action · 12 KB"
    private var summary: String {
        [d.kind, d.size.map { bytes(Int64($0)) }].compactMap { $0 }.joined(separator: " · ")
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.path)])
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.path, forType: .string)
    }

    private var sharedText: String {
        guard d.isShared else { return "No" }
        switch d.sharedRole {
        case .owner?: return "Yes, you are the owner"
        case .participant?: return "Yes, shared with you"
        default: return "Yes"
        }
    }

    @ViewBuilder
    private func dateRow(_ title: String, _ date: Date?) -> some View {
        LabeledContent(title) {
            if let date { DateText(prefix: nil, date: date) } else { Text("—").foregroundStyle(.secondary) }
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// An absolute date with the relative time below it, kept current.
private struct DateText: View {
    let prefix: String?
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .trailing, spacing: 1) {
                Text([prefix, date.formatted(date: .abbreviated, time: .standard)]
                    .compactMap { $0 }.joined(separator: " "))
                    .monospacedDigit()
                Text(relative(to: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relative(to now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named   // "now", "yesterday"
        f.unitsStyle = .full
        return f.localizedString(for: min(date, now), relativeTo: now)
    }
}

/// The file's location as a breadcrumb with folder icons (`NSPathControl`), as in
/// Finder's path bar. Clicking a folder shows it in Finder; the context menu
/// copies the path or shows the item.
private struct PathControl: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.isEditable = false
        control.focusRingType = .none
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.menu = context.coordinator.menu
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        if control.url != url { control.url = url }
        context.coordinator.url = url
    }

    @MainActor
    final class Coordinator: NSObject {
        var url: URL?
        lazy var menu: NSMenu = {
            let menu = NSMenu()
            let copy = NSMenuItem(title: "Copy as Pathname", action: #selector(copyPath), keyEquivalent: "")
            copy.target = self
            let show = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder), keyEquivalent: "")
            show.target = self
            menu.items = [copy, show]
            return menu
        }()

        @objc func clicked(_ sender: NSPathControl) {
            guard let item = sender.clickedPathItem?.url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([item])
        }

        @objc func copyPath() {
            guard let url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }

        @objc func showInFinder() {
            guard let url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

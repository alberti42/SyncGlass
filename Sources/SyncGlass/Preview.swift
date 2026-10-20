#if DEBUG
import AppKit
import SwiftUI

/// Debug aid: `SyncGlass --preview` opens the panel, Settings and the welcome
/// screen as ordinary windows, with sample transfers, for screenshots.
/// Add `--preview-live` to show the tracker's live data in the panel instead.
@MainActor
enum Preview {
    private static var windows: [NSWindow] = []

    static func show(model: StatusModel) {
        if !CommandLine.arguments.contains("--preview-live") { showSampleData(in: model) }

        open(StatusPanel(model: model).background(.regularMaterial), title: "Panel", at: NSPoint(x: 120, y: 900))
        open(SettingsView(), title: "Settings", at: NSPoint(x: 560, y: 900))
        open(WelcomeView(choice: .constant(.iCloudDrive), openAtLogin: .constant(true), done: {}),
             title: "Welcome", at: NSPoint(x: 1140, y: 900))
        if let path = model.recents.first?.path ?? model.transfers.first {
            open(FileInfoView(path: path).frame(height: 1000), title: "File Info", at: NSPoint(x: 1640, y: 1100))
        }
        NSApp.activate()
    }

    private static func showSampleData(in model: StatusModel) {
        let files = sampleFiles()
        var s = TrackerSnapshot()
        s.status = .transferring
        s.totalTransfers = files
        s.transferCount = max(0, files.count - 2)
        s.totalTransferCount = files.count
        s.completedTransfers = Set(files.prefix(2))
        s.completedTransferCount = min(2, files.count)
        s.downloadingTransfers = Set(files.suffix(1))
        s.recentTransfers = Tracker.shared.snapshot().recentTransfers
        model.isPreview = true
        model.update(s)
    }

    private static func open<V: View>(_ view: V, title: String, at origin: NSPoint) {
        let host = NSHostingController(rootView: view)
        host.sceneBridgingOptions = [.toolbars, .title]   // show SwiftUI toolbars and titles
        let w = NSWindow(contentViewController: host)
        w.title = "Preview – \(title)"
        w.setFrameTopLeftPoint(origin)
        w.makeKeyAndOrderFront(nil)
        windows.append(w)
    }

    private static func sampleFiles() -> [String] {
        let root = Paths.iCloudDrive
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return names.filter { !$0.hasPrefix(".") }.prefix(6).map { (root as NSString).appendingPathComponent($0) }
    }
}
#endif

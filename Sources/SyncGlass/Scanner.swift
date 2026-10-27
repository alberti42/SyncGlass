import AppKit
import SwiftUI

/// Scan for Transfers.
///
/// Walks a folder for files that are not uploaded yet and hands them to the
/// tracker as the transfers in flight. The tracker is paused during the scan.
@MainActor
final class Scanner: ObservableObject {
    private static var current: Scanner?

    @Published var currentPath = ""
    @Published var foundCount = 0
    private let cancelFlag = CancelFlag()
    private var window: NSWindow?

    /// From Settings > General: choose the folder first.
    static func scanWithPanel() {
        if let path = FolderPicker.choose(
            startingAt: Prefs.folder,
            message: "Please choose the folder to scan for transfers in progress.",
            prompt: "Scan")
        {
            scan(path)
        }
    }

    private static func scan(_ path: String) {
        guard current == nil else {
            current?.window?.makeKeyAndOrderFront(nil)
            return
        }
        let scanner = Scanner()
        current = scanner
        scanner.run(path)
    }

    private func run(_ root: String) {
        let w = NSWindow(contentViewController: NSHostingController(rootView: ScannerView(scanner: self)))
        w.title = "Scan for Transfers"
        w.styleMask = [.titled, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)

        Tracker.shared.pause()
        var roots = [root]
        for dir in [FileManager.SearchPathDirectory.documentDirectory, .desktopDirectory] {
            if let p = NSSearchPathForDirectoriesInDomains(dir, .userDomainMask, true).last, PathChecks.isTracked(p) {
                roots.append(p)
            }
        }
        let ignoreSymlinks = Prefs.ignoreSymbolicLinks
        let flag = cancelFlag
        let scanner = self   // kept alive by `Scanner.current` until `finish`
        Task.detached(priority: .userInitiated) {
            var found: [String] = []
            var lastUpdate = CFAbsoluteTimeGetCurrent()
            func walk(_ dir: String) -> Bool {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return true }
                for name in names {
                    if flag.isSet { return false }
                    let path = (dir as NSString).appendingPathComponent(name)
                    let state = ItemState(path: path)
                    guard state.exists, state.isUbiquitous, !state.isHidden, !(ignoreSymlinks && state.isSymbolicLink)
                    else { continue }
                    if CFAbsoluteTimeGetCurrent() - lastUpdate > 0.1 {
                        lastUpdate = CFAbsoluteTimeGetCurrent()
                        let shown = (path as NSString).abbreviatingWithTildeInPath
                        Task { @MainActor in scanner.currentPath = shown }
                    }
                    if !state.isUploaded && (!state.isDirectory || state.isPackage) && state.containsBytes
                        && !PathChecks.isInsideImplicitPackage(path)
                    {
                        found.append(path)
                        let n = found.count
                        Task { @MainActor in scanner.foundCount = n }
                    }
                    if state.isDirectory && !state.isPackage && !walk(path) { return false }
                }
                return true
            }
            for r in roots where !walk(r) { break }
            let result = found
            await scanner.finish(result)
        }
    }

    func cancel() { cancelFlag.set() }

    /// `scannerDidStop:userCanceled:`
    private func finish(_ found: [String]) {
        window?.close()
        window = nil
        Scanner.current = nil
        if !cancelFlag.isSet {
            if found.isEmpty {
                let alert = NSAlert()
                alert.messageText = "No transfers in progress"
                alert.informativeText = "Every file in the folder is uploaded to iCloud."
                alert.runModal()
            } else {
                Tracker.shared.setExistingTransfers(found)
            }
        }
        Tracker.shared.resume()
    }
}

private struct ScannerView: View {
    @ObservedObject var scanner: Scanner

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.tint(.accentColor.opacity(0.2)), in: .circle)
            VStack(alignment: .leading, spacing: 8) {
                Text("Scanning for Transfers").font(.headline)
                ProgressView().progressViewStyle(.linear)
                Text(scanner.currentPath.isEmpty ? "Starting…" : scanner.currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Text(scanner.foundCount == 1 ? "1 file not yet uploaded" : "\(scanner.foundCount) files not yet uploaded")
                        .font(.callout)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { scanner.cancel() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

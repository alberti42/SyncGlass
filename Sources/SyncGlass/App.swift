import AppKit
import Network
import SwiftUI

@main
struct SyncGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }

        WindowGroup("File Info", id: FileInfo.windowID, for: String.self) { $path in
            if let path { FileInfoView(path: path) }
        }
        .defaultSize(width: 480, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// The menu-bar icon. `MenuBarIcon` returns template images, which the menu bar
/// tints for the current appearance.
private struct MenuBarLabel: View {
    let model: StatusModel

    var body: some View {
        Image(nsImage: model.menuBarImage)
            .accessibilityLabel(MenuBarIcon.accessibilityLabel(for: model.snapshot, isReachable: model.isReachable,
                                                               stuckCount: model.stuckCount))
    }
}

/// Launch sequence, tracker delegate, reachability and preference observers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, TrackerDelegate {
    let model = StatusModel()
    private var tracker: Tracker!
    private let notifier = Notifier()
    private let fileProgress = FileProgressMonitor()
    private let pathMonitor = NWPathMonitor()
    private var defaultsObserver: NSObjectProtocol?
    private var lastFolder = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--login-item-status") {
            print("login item: \(LoginItem.status.rawValue) (\(LoginItem.statusDescription))")
            exit(0)
        }
        if CommandLine.arguments.contains("--queue-status") {
            printQueueStatus()
            return
        }

        Prefs.registerDefaults()

        let firstLaunch = !Prefs.store.bool(forKey: PrefKey.launchedFirstTime)
        if firstLaunch {
            Prefs.store.set(true, forKey: PrefKey.launchedFirstTime)
            WelcomeWindow.runModal()
        }
        if !FileManager.default.fileExists(atPath: Prefs.folder) {
            FolderPicker.locateICloudDriveFolder(
                message: "Choose the iCloud folder to monitor. You only need to do this once.")
        }

        tracker = Tracker(directory: Prefs.folder)
        tracker.delegate = self
        lastFolder = Prefs.folder

        observeDefaults()
        startReachability()
        notifier.requestAuthorization()
        Updater.shared.start()
        tracker.start()
        model.fileProgressMonitor = fileProgress
        model.update(tracker.snapshot())

        #if DEBUG
        if CommandLine.arguments.contains("--watch-stuck-files") { model.toggleStuckFileWatch() }
        if CommandLine.arguments.contains("--preview") { Preview.show(model: model) }
        #endif
    }

    /// `--queue-status`: prints the items in iCloud Drive's queue with the files
    /// they resolve to, and exits.
    private func printQueueStatus() {
        Task {
            let now = Date()
            let output = await Task.detached { ICloudQueue.readStatus() }.value
            let items = ICloudQueue.parse(output ?? "", now: now)
            print("\(items.count) items in iCloud Drive's queue")
            for item in items {
                let path = await ICloudQueue.resolve(item) ?? "not found: \(item.folder) \(item.name)"
                var fields = [item.state ?? "-", item.operation?.kind ?? "-"]
                if let attempts = item.operation?.attempts { fields.append("attempts \(attempts)") }
                if let last = item.operation?.lastAttempt { fields.append("last attempt \(Int(now.timeIntervalSince(last))) s ago") }
                print("\(fields.joined(separator: ", ")): \(path)")
            }
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker?.saveEventID()
    }

    // MARK: TrackerDelegate

    func trackerStatusChanged(_ snapshot: TrackerSnapshot) {
        fileProgress.track(Set(snapshot.totalTransfers).subtracting(snapshot.completedTransfers))
        model.update(snapshot)
        notifier.trackerStatusChanged(snapshot)
    }

    // MARK: Observers

    /// Follow changes to the monitored folder and the menu-bar settings.
    private func observeDefaults() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: Prefs.store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.defaultsChanged() }
        }
    }

    private func defaultsChanged() {
        model.preferencesChanged()
        let folder = Prefs.folder
        if folder != lastFolder {
            lastFolder = folder
            model.folderChanged()
            tracker.setDirectory(folder)
        }
    }

    /// Pause the tracker while the Mac is offline.
    private func startReachability() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in
                self?.tracker.networkReachabilityChanged(isReachable: reachable)
                self?.model.setReachable(reachable)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "SyncGlass.reachability"))
    }
}

/// First-launch window: what to track, whether to open at login, and whether to
/// check for updates automatically.
@MainActor
enum WelcomeWindow {
    static func runModal() {
        var choice = WelcomeView.Choice.iCloudDrive
        var openAtLogin = true
        var checkForUpdates = true
        let view = WelcomeView(
            choice: Binding(get: { choice }, set: { choice = $0 }),
            openAtLogin: Binding(get: { openAtLogin }, set: { openAtLogin = $0 }),
            checkForUpdates: Binding(get: { checkForUpdates }, set: { checkForUpdates = $0 }),
            done: { NSApp.stopModal() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        NSApp.activate()
        NSApp.runModal(for: window)
        window.close()

        switch choice {
        case .everything:
            Prefs.store.set(Paths.mobileDocuments, forKey: PrefKey.iCloudDriveFolder)
            Prefs.store.set([String](), forKey: PrefKey.includePatterns)
            Prefs.store.set([String](), forKey: PrefKey.excludePatterns)
        case .iCloudDrive:
            Prefs.store.set(Paths.iCloudDrive, forKey: PrefKey.iCloudDriveFolder)
        }
        if openAtLogin { try? LoginItem.setEnabled(true) }
        Updater.shared.automaticallyChecks = checkForUpdates
    }
}

struct WelcomeView: View {
    enum Choice: Hashable { case iCloudDrive, everything }

    @Binding var choice: Choice
    @Binding var openAtLogin: Bool
    @Binding var checkForUpdates: Bool
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 88, height: 88)
                .glassEffect(.regular.tint(.accentColor.opacity(0.2)), in: .circle)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Welcome to SyncGlass").font(.title.weight(.semibold))
                Text("SyncGlass lives in the menu bar and shows which files iCloud is uploading and downloading.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ChoiceCard(
                    title: "iCloud Drive",
                    detail: "Files in iCloud Drive, including Desktop and Documents.",
                    systemImage: "folder",
                    isSelected: choice == .iCloudDrive) { choice = .iCloudDrive }
                ChoiceCard(
                    title: "All iCloud Documents",
                    detail: "iCloud Drive plus the iCloud folders of every app.",
                    systemImage: "square.stack.3d.up",
                    isSelected: choice == .everything) { choice = .everything }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open SyncGlass at login", isOn: $openAtLogin)
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
            }
            .toggleStyle(.checkbox)

            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.glass)
                Spacer()
                Button("Continue", action: done)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)

            Text("You can change these choices later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 440)
    }
}

private struct ChoiceCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(12)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.15)) : .regular, in: .rect(cornerRadius: 14))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

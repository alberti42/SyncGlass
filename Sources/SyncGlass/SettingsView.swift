import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window. Controls bind to user defaults through `@AppStorage(PrefKey.…)`.
/// Each tab has its own height; the window resizes when the tab changes.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralPane().frame(width: 520, height: Self.generalHeight)
            }
            Tab("Notifications", systemImage: "bell.badge") { NotificationsPane().frame(width: 520, height: 560) }
            Tab("History", systemImage: "clock.arrow.circlepath") { HistoryPane().frame(width: 520, height: 560) }
            Tab("Filters", systemImage: "line.3.horizontal.decrease") { FiltersPane().frame(width: 520, height: 560) }
        }
    }

    /// General needs 810 pt. On a smaller screen it gets the screen's height below
    /// the menu bar and above the Dock, minus 100 pt for the title bar and the tabs,
    /// and the form scrolls.
    private static var generalHeight: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 100
        return max(560, min(810, available))
    }
}

// MARK: General

private struct GeneralPane: View {
    @AppStorage(PrefKey.iCloudDriveFolder) private var folder = Paths.iCloudDrive
    @AppStorage(PrefKey.pollingMode) private var polling = PollingMode.economical.rawValue
    @AppStorage(PrefKey.statusItemMode) private var statusMode = StatusItemMode.image.rawValue
    @AppStorage(PrefKey.trackIncomingDownloads) private var trackDownloads = true
    @AppStorage(PrefKey.ignoreHiddenFiles) private var ignoreHidden = true
    @AppStorage(PrefKey.ignoreSymbolicLinks) private var ignoreSymlinks = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    Menu {
                        Button("iCloud Drive") { folder = Paths.iCloudDrive }
                        Button("All iCloud Documents") { folder = Paths.mobileDocuments }
                        Divider()
                        Button("Choose…") {
                            if let p = FolderPicker.choose(startingAt: folder) { folder = p }
                        }
                    } label: {
                        Label(folderName, systemImage: "folder")
                    }
                    .fixedSize()
                }
                Picker("Check for changes", selection: $polling) {
                    Text("Frequently").tag(PollingMode.moderate.rawValue)
                    Text("Economically").tag(PollingMode.economical.rawValue)
                }
                Toggle("Track incoming downloads", isOn: $trackDownloads)
                Toggle("Ignore hidden files", isOn: $ignoreHidden)
                Toggle("Ignore symbolic links", isOn: $ignoreSymlinks)
            } header: {
                Text("Monitoring")
            } footer: {
                Text("Frequent checking re-checks 100 files per pass, economical checking 25.")
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show transfer progress in the icon", isOn: Binding(
                    get: { statusMode == StatusItemMode.progressWheel.rawValue },
                    set: { statusMode = ($0 ? StatusItemMode.progressWheel : .image).rawValue }
                ))
            }

            LoginItemSection()

            UpdatesSection()

            Section {
                Button("Scan for Transfers…") { Scanner.scanWithPanel() }
            } footer: {
                Text("SyncGlass finds transfers that started while it was not running from the changes macOS records. A scan is rarely needed: only when Transfers stays empty although iCloud Drive is uploading, for example after the first launch. It checks every file in the folder, so it takes longer the more files the folder holds.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var folderName: String {
        switch folder {
        case Paths.iCloudDrive: return "iCloud Drive"
        case Paths.mobileDocuments: return "All iCloud Documents"
        default: return (folder as NSString).abbreviatingWithTildeInPath
        }
    }
}

/// Open at Login through the embedded login helper (`LoginItem`).
private struct LoginItemSection: View {
    @State private var status = LoginItem.status
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            Toggle("Open at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { enable in
                    do {
                        try LoginItem.setEnabled(enable)
                        error = nil
                    } catch let e {
                        error = e.localizedDescription
                    }
                    status = LoginItem.status
                }
            ))
            if status == .requiresApproval {
                LabeledContent {
                    Button("Open Login Items…") { LoginItem.openSystemSettings() }
                } label: {
                    Label("Needs approval in System Settings", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Startup")
        } footer: {
            Text(error ?? LoginItem.statusDescription)
                .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
        .onAppear { status = LoginItem.status }
        .onChange(of: scenePhase) { _, _ in status = LoginItem.status }
    }
}

/// Sparkle's update settings (`Updater`).
private struct UpdatesSection: View {
    @Bindable private var updater = Updater.shared

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
            Button("Check Now") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        } header: {
            Text("Updates")
        } footer: {
            Text(updater.isAvailable
                ? "SyncGlass checks once a week."
                : "Updates are only available in SyncGlass.app.")
                .foregroundStyle(.secondary)
        }
        .disabled(!updater.isAvailable)
    }
}

// MARK: Notifications

private struct NotificationsPane: View {
    @AppStorage(PrefKey.showNotifications) private var showNotifications = true
    @AppStorage(PrefKey.elapsedTimeNotificationLimit) private var elapsedLimit = 30
    @AppStorage(PrefKey.showDownloadNotifications) private var showDownloadNotifications = true
    @AppStorage(PrefKey.trackIncomingDownloads) private var trackDownloads = true
    @AppStorage(PrefKey.downloadBatchDelay) private var downloadBatchDelay = 15
    @AppStorage(PrefKey.notificationSound) private var sound = "Default"

    var body: some View {
        Form {
            Section {
                Toggle("Notify when uploads finish", isOn: $showNotifications)
                Stepper(value: $elapsedLimit, in: 0...3600, step: 5) {
                    LabeledContent("Only after transfers longer than", value: "\(elapsedLimit) s")
                }
                .disabled(!showNotifications)
            } header: {
                Text("Uploads")
            } footer: {
                Text("Short transfers finish without a notification.").foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify when downloads finish", isOn: $showDownloadNotifications)
                Stepper(value: $downloadBatchDelay, in: 1...300) {
                    LabeledContent("Group downloads arriving within", value: "\(downloadBatchDelay) s")
                }
            } header: {
                Text("Downloads")
            }
            .disabled(!trackDownloads)

            Section("Sound") {
                Picker("Notification sound", selection: $sound) {
                    Text("Default").tag("Default")
                    Text("None").tag("None")
                    Divider()
                    ForEach(Notifier.systemSounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: sound) { _, name in NSSound(named: name)?.play() }
                Button("Open Notification Settings…") {
                    // `?id=` selects this app's page in System Settings > Notifications.
                    let id = Bundle.main.bundleIdentifier.map { "?id=\($0)" } ?? ""
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension\(id)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: History

private struct HistoryPane: View {
    @AppStorage(PrefKey.enableLogging) private var enableLogging = true
    @AppStorage(PrefKey.downloadErrorLogging) private var keepDownloadHistory = true
    @AppStorage(PrefKey.clearLogAfterSize) private var clearLogAfter = 25
    @AppStorage(PrefKey.recentFilesLimit) private var recentLimit = 100

    var body: some View {
        Form {
            Section {
                Toggle("Keep a history log", isOn: $enableLogging)
                Toggle("Include downloads", isOn: $keepDownloadHistory)
                    .disabled(!enableLogging)
                Stepper(value: $clearLogAfter, in: 1...1000) {
                    LabeledContent("Clear the log when it reaches", value: "\(clearLogAfter) MB")
                }
                .disabled(!enableLogging)
            } header: {
                Text("History Log")
            } footer: {
                Text((Paths.historyLog.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Recent Files") {
                Stepper(value: $recentLimit, in: 10...1000, step: 10) {
                    LabeledContent("Remember up to", value: "\(recentLimit) files")
                }
            }

            Section {
                HStack {
                    Button("Show Log in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.historyLog])
                    }
                    Spacer()
                    Button("Clear History…", role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = "Clear the transfer history?"
                        alert.informativeText = "The history log and the list of recent files are deleted. This cannot be undone."
                        alert.addButton(withTitle: "Clear History")
                        alert.addButton(withTitle: "Cancel")
                        alert.buttons.first?.hasDestructiveAction = true
                        if alert.runModal() == .alertFirstButtonReturn { Tracker.shared?.clearHistory() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Filters

/// Editable include and exclude lists of regular expressions.
private struct FiltersPane: View {
    var body: some View {
        Form {
            PatternSection(
                key: PrefKey.includePatterns,
                title: "Track Only",
                footer: "Only paths matching one of these regular expressions are tracked. An empty list tracks every path.")
            PatternSection(
                key: PrefKey.excludePatterns,
                title: "Never Track",
                footer: "Paths matching one of these regular expressions are never tracked.")
            Section {
                Button("Restore Default Filters") {
                    Prefs.store.set(Prefs.defaultIncludePatterns, forKey: PrefKey.includePatterns)
                    Prefs.store.set([String](), forKey: PrefKey.excludePatterns)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PatternSection: View {
    let key: String
    let title: String
    let footer: String
    @State private var patterns: [String] = []

    var body: some View {
        Section {
            ForEach(patterns.indices, id: \.self) { i in
                HStack {
                    TextField("Regular expression", text: Binding(
                        get: { patterns.indices.contains(i) ? patterns[i] : "" },
                        set: { patterns[i] = $0; save() }
                    ))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isValid(patterns[i]) ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                    Button {
                        patterns.remove(at: i)
                        save()
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove pattern")
                }
            }
            Button("Add Pattern", systemImage: "plus") {
                patterns.append("")
                save()
            }
            .buttonStyle(.borderless)
        } header: {
            Text(title)
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
        .onAppear { patterns = Prefs.store.stringArray(forKey: key) ?? [] }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let stored = Prefs.store.stringArray(forKey: key) ?? []
            if stored != patterns { patterns = stored }
        }
    }

    private func isValid(_ pattern: String) -> Bool {
        pattern.isEmpty || (try? NSRegularExpression(pattern: pattern)) != nil
    }

    private func save() { Prefs.store.set(patterns, forKey: key) }
}

// MARK: Folder picker

@MainActor
enum FolderPicker {
    static func choose(startingAt folder: String, message: String? = nil, prompt: String = "Choose") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folder)
        panel.message = message ?? "Choose the iCloud folder to monitor. All changes inside the folder are tracked."
        panel.prompt = prompt
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// Ask until the user picks a folder or quits.
    static func locateICloudDriveFolder(message: String) {
        while true {
            if let path = choose(startingAt: Paths.iCloudDrive, message: message) {
                if path.localizedCaseInsensitiveContains("Mobile Documents") || confirmUnusualFolder() {
                    Prefs.store.set(path, forKey: PrefKey.iCloudDriveFolder)
                    return
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "SyncGlass needs an iCloud folder to monitor."
                alert.informativeText = "Choose your iCloud Drive folder, or quit SyncGlass."
                alert.addButton(withTitle: "Choose Folder…")
                alert.addButton(withTitle: "Quit")
                if alert.runModal() != .alertFirstButtonReturn { NSApp.terminate(nil) }
            }
        }
    }

    private static func confirmUnusualFolder() -> Bool {
        let alert = NSAlert()
        alert.messageText = "This folder is not inside iCloud."
        alert.informativeText = "Changes to iCloud Drive are not tracked unless the folder is inside ~/Library/Mobile Documents."
        alert.addButton(withTitle: "Use Anyway")
        alert.addButton(withTitle: "Choose Another")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

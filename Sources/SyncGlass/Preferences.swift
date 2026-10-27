import Foundation

/// User-defaults keys.
enum PrefKey {
    static let showNotifications = "ShowNotifications"
    static let enableLogging = "EnableLogging"
    static let clearLogAfterSize = "ClearLogAfterSize"
    static let iCloudDriveFolder = "ICloudDriveFolder"
    static let pollingMode = "PollingMode"
    static let statusItemMode = "StatusItemMode"
    static let lastTransferDate = "LastTransferDate"
    static let ignoreHiddenFiles = "IgnoreHiddenFiles"
    static let ignoreSymbolicLinks = "IgnoreSymbolicLinks"
    static let trackIncomingDownloads = "TrackIncomingDownloads"
    static let includePatterns = "IncludePatterns"
    static let excludePatterns = "ExcludePatterns"
    static let elapsedTimeNotificationLimit = "ElapsedTimeNotificationLimit"
    static let downloadErrorLogging = "DownloadErrorLogging"
    static let downloadBatchDelay = "DownloadBatchDelay"
    static let showDownloadNotifications = "ShowDownloadNotifications"
    static let notificationSound = "NotificationSound"
    static let recentFilesLimit = "RecentFilesLimit"
    static let iCloudDiskUsage = "ICloudDiskUsage"
    static let selectedTabIndex = "selectedTabIndex"
    static let launchedFirstTime = "launchedFirstTime"
    /// The ID of the last FSEvents event the tracker received (`Tracker.startEventID`).
    static let lastEventID = "LastFSEventID"
}

enum StatusItemMode: Int {
    case image = 0
    case progressWheel = 1
}

/// How many paths in flight are re-checked per pass. Settings offers
/// Moderate ("Frequently") and Economical; 2 is not offered in the UI.
enum PollingMode: Int {
    case moderate = 0
    case economical = 1
    case aggressive = 2

    var batchSize: Int {
        switch self {
        case .moderate: return 100
        case .economical: return 25
        case .aggressive: return 200
        }
    }
}

enum Paths {
    static let mobileDocuments = NSString(string: "~/Library/Mobile Documents").expandingTildeInPath
    static let iCloudDrive = NSString(string: "~/Library/Mobile Documents/com~apple~CloudDocs").expandingTildeInPath

    /// The app's data folder, named after the bundle identifier. The original
    /// iCloudStatus by The Alchemist Guild uses `Application Support/iCloudStatus`;
    /// this app must not read or write that folder.
    static var supportFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("io.alberti42.SyncGlass", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var historyLog: URL { supportFolder.appendingPathComponent("transfer_history.log") }
}

enum Prefs {
    static let store = UserDefaults.standard

    static let defaultIncludePatterns = [
        #"\/Mobile\s+Documents\/com~apple~CloudDocs"#,
        #"\/Mobile\s+Documents\/.*\/Documents"#,
        #"\/Mobile\s+Documents\/.*\/CloudStore"#,
    ]

    /// Default values. Registered defaults apply until the user changes a setting.
    static func registerDefaults() {
        store.register(defaults: [
            PrefKey.iCloudDriveFolder: Paths.iCloudDrive,
            PrefKey.includePatterns: defaultIncludePatterns,
            PrefKey.excludePatterns: [String](),
            PrefKey.showNotifications: true,
            PrefKey.elapsedTimeNotificationLimit: 30,
            PrefKey.enableLogging: true,
            PrefKey.clearLogAfterSize: 25,
            PrefKey.pollingMode: PollingMode.economical.rawValue,
            PrefKey.statusItemMode: StatusItemMode.image.rawValue,
            PrefKey.ignoreHiddenFiles: true,
            PrefKey.ignoreSymbolicLinks: true,
            PrefKey.trackIncomingDownloads: true,
            PrefKey.downloadErrorLogging: true,
            PrefKey.showDownloadNotifications: true,
            PrefKey.downloadBatchDelay: 15,
            PrefKey.recentFilesLimit: 100,
            PrefKey.selectedTabIndex: 0,
        ])
    }

    static var folder: String {
        NSString(string: store.string(forKey: PrefKey.iCloudDriveFolder) ?? Paths.iCloudDrive).expandingTildeInPath
    }

    static var includePatterns: [String] { store.stringArray(forKey: PrefKey.includePatterns) ?? [] }
    static var excludePatterns: [String] { store.stringArray(forKey: PrefKey.excludePatterns) ?? [] }
    static var trackIncomingDownloads: Bool { store.bool(forKey: PrefKey.trackIncomingDownloads) }
    static var ignoreHiddenFiles: Bool { store.bool(forKey: PrefKey.ignoreHiddenFiles) }
    static var ignoreSymbolicLinks: Bool { store.bool(forKey: PrefKey.ignoreSymbolicLinks) }
    static var enableLogging: Bool { store.bool(forKey: PrefKey.enableLogging) }
    static var downloadErrorLogging: Bool { store.bool(forKey: PrefKey.downloadErrorLogging) }
    static var downloadBatchDelay: Double { store.double(forKey: PrefKey.downloadBatchDelay) }
    static var clearLogAfterSize: Int { store.integer(forKey: PrefKey.clearLogAfterSize) }
    static var recentFilesLimit: Int { max(1, store.integer(forKey: PrefKey.recentFilesLimit)) }
    static var pollingMode: PollingMode { PollingMode(rawValue: store.integer(forKey: PrefKey.pollingMode)) ?? .economical }
    static var statusItemMode: StatusItemMode { StatusItemMode(rawValue: store.integer(forKey: PrefKey.statusItemMode)) ?? .image }
}

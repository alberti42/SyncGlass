import AppKit
import Observation
import Sparkle

/// Software updates through Sparkle. `Resources/Info.plist` holds the appcast URL
/// (`SUFeedURL`), the public EdDSA key (`SUPublicEDKey`) and the interval between
/// automatic checks (`SUScheduledCheckInterval`, 7 days).
@MainActor
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// Sparkle reads its settings from the app bundle, so an unbundled build
    /// (`.build/debug/SyncGlass`) does not start the updater.
    let isAvailable = Bundle.main.bundleURL.pathExtension == "app"

    /// False while a check or an update is in progress.
    private(set) var canCheckForUpdates = false

    /// The version of an update that a scheduled check found and the user has
    /// not looked at yet. The panel's menu shows it.
    private(set) var pendingVersion: String?

    /// Sparkle stores this setting in user defaults (`SUEnableAutomaticChecks`).
    /// Until it is set, Sparkle asks the user on the second launch.
    var automaticallyChecks = false {
        didSet {
            if isAvailable, controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    }

    func start() {
        guard isAvailable else { return }
        controller.startUpdater()
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.automaticallyChecksForUpdates
                Task { @MainActor in self?.automaticallyChecks = value }
            },
        ]
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    /// SyncGlass has no Dock icon. With gentle reminders, Sparkle shows the update
    /// found by a scheduled check without taking the focus, and the panel's menu
    /// offers the update until the user opens it.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.pendingVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}

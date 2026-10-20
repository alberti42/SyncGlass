import AppKit
import UserNotifications

/// Posts notifications when transfers finish.
///
/// Finished batches are added up; the notification is posted 1 s after the last
/// batch, or after `DownloadBatchDelay` when incoming downloads are tracked.
@MainActor
final class Notifier {
    private struct Stats {
        var elapsedTransferTime: Double = 0
        var completedDownloadCount = 0
        var completedTransferCount = 0
        var totalTransferCount = 0
    }

    private var stats = Stats()
    private var pending: DispatchWorkItem?

    static var systemSounds: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func trackerStatusChanged(_ s: TrackerSnapshot) {
        pending?.cancel()
        guard s.isFinishedTransferring else { return }
        stats.elapsedTransferTime += s.elapsedTransferTime
        stats.completedDownloadCount += s.previousCompletedDownloadCount
        stats.completedTransferCount += s.completedTransferCount
        stats.totalTransferCount += s.totalTransferCount

        let delay = Prefs.trackIncomingDownloads ? Prefs.downloadBatchDelay : 1
        let work = DispatchWorkItem { [weak self] in self?.show() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show() {
        let s = stats
        stats = Stats()

        if s.completedDownloadCount > 0 && s.totalTransferCount == 0
            && Prefs.store.bool(forKey: PrefKey.showDownloadNotifications)
        {
            let n = s.completedDownloadCount
            post(n == 1 ? "1 download complete." : "\(n) downloads complete.")
        }

        let limit = Double(Prefs.store.integer(forKey: PrefKey.elapsedTimeNotificationLimit))
        if s.totalTransferCount > 0 && s.completedTransferCount > 0 && s.elapsedTransferTime > limit
            && Prefs.store.bool(forKey: PrefKey.showNotifications)
        {
            let done = s.completedTransferCount, all = s.totalTransferCount
            if done == all {
                post(done == 1 ? "1 transfer complete." : "\(done) transfers complete.")
            } else {
                let pct = Int((Double(done) / Double(all) * 100).rounded())
                post("Completed \(done) of \(all) transfers (\(pct)%)")
            }
        }
    }

    private func post(_ subtitle: String) {
        let sound = Prefs.store.string(forKey: PrefKey.notificationSound) ?? "Default"
        let content = UNMutableNotificationContent()
        content.title = "iCloud Drive"
        content.subtitle = subtitle
        // Notification sounds must live in a Sounds folder the system searches;
        // the system alert sounds are played directly instead.
        if sound == "Default" {
            content.sound = .default
        } else if sound != "None" {
            NSSound(named: sound)?.play()
        }
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("SyncGlass: \(subtitle)")
            return
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

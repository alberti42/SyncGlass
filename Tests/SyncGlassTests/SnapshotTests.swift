import Foundation
import Testing
@testable import SyncGlass

@Suite struct TrackerSnapshotTests {
    @Test func progressWithoutTransfersIsZero() {
        #expect(TrackerSnapshot().progress == 0)
    }

    @Test func progressIsCompletedOverTotal() {
        var s = TrackerSnapshot()
        s.completedTransferCount = 3
        s.totalTransferCount = 4
        #expect(s.progress == 0.75)
    }

    @Test func progressIsClampedToOne() {
        var s = TrackerSnapshot()
        s.completedTransferCount = 5
        s.totalTransferCount = 4
        #expect(s.progress == 1)
    }

    @Test func downloadingOnly() {
        var s = TrackerSnapshot()
        #expect(!s.isDownloadingOnly)
        s.transferCount = 2
        s.downloadingTransfers = ["/a", "/b"]
        #expect(s.isDownloadingOnly)
        s.downloadingTransfers = ["/a"]
        #expect(!s.isDownloadingOnly)
    }
}

@MainActor @Suite struct MenuBarSymbolTests {
    func snapshot(_ status: TrackerSnapshot.Status, downloads: Int = 0, transfers: Int = 0) -> TrackerSnapshot {
        var s = TrackerSnapshot()
        s.status = status
        s.transferCount = transfers
        s.downloadingTransfers = Set((0..<downloads).map { "/file\($0)" })
        return s
    }

    @Test func offlineWinsOverEveryStatus() {
        #expect(MenuBarIcon.symbol(for: snapshot(.transferring, transfers: 1), isReachable: false) == .offline)
        #expect(MenuBarIcon.symbol(for: snapshot(.transferring, transfers: 1), isReachable: false, stuckCount: 1) == .offline)
    }

    @Test func stuckWinsOverTransfers() {
        #expect(MenuBarIcon.symbol(for: snapshot(.transferring, transfers: 2), isReachable: true, stuckCount: 1) == .stuck)
        #expect(MenuBarIcon.symbol(for: snapshot(.transferring, transfers: 2), isReachable: true, stuckCount: 0) == .uploading)
    }

    @Test func idleAndSyncing() {
        #expect(MenuBarIcon.symbol(for: snapshot(.idle), isReachable: true) == .idle)
        #expect(MenuBarIcon.symbol(for: snapshot(.syncing), isReachable: true) == .syncing)
    }

    @Test func uploadUnlessEveryTransferIsADownload() {
        #expect(MenuBarIcon.symbol(for: snapshot(.transferring, downloads: 2, transfers: 2), isReachable: true) == .downloading)
        #expect(MenuBarIcon.symbol(for: snapshot(.transferring, downloads: 1, transfers: 2), isReachable: true) == .uploading)
    }
}

@MainActor @Suite struct DetailTextTests {
    @Test func syncing() {
        var s = TrackerSnapshot()
        s.status = .syncing
        s.completedDownloadCount = 1
        #expect(StatusModel.detailText(for: s) == "Syncing changes to 1 file…")
        s.completedDownloadCount = 3
        #expect(StatusModel.detailText(for: s) == "Syncing changes to 3 files…")
    }

    @Test func transferring() {
        var s = TrackerSnapshot()
        s.status = .transferring
        s.transferCount = 1
        #expect(StatusModel.detailText(for: s) == "1 file in progress")
        s.transferCount = 2
        #expect(StatusModel.detailText(for: s) == "2 files in progress")
    }
}

/// `recent_transfers.plist` must stay readable across versions.
@Suite struct RecentTransferFormatTests {
    @Test func kindRawValuesAreStable() {
        #expect(RecentTransfer.Kind.upload.rawValue == "upload")
        #expect(RecentTransfer.Kind.download.rawValue == "download")
        #expect(RecentTransfer.Kind.change.rawValue == "change")
    }

    @Test func propertyListRoundTrip() throws {
        let entries = [
            RecentTransfer(path: "/a.txt", date: Date(timeIntervalSince1970: 1_700_000_000), kind: .upload),
            RecentTransfer(path: "/b.txt", date: Date(timeIntervalSince1970: 1_700_000_100), kind: .change),
        ]
        let data = try PropertyListEncoder().encode(entries)
        #expect(try PropertyListDecoder().decode([RecentTransfer].self, from: data) == entries)
    }

    @Test func verbs() {
        #expect(RecentTransfer.Kind.upload.verb == "Uploaded")
        #expect(RecentTransfer.Kind.download.verb == "Downloaded")
        #expect(RecentTransfer.Kind.change.verb == "Synced")
    }
}

@Suite struct PollingModeTests {
    @Test func batchSizes() {
        #expect(PollingMode.moderate.batchSize == 100)
        #expect(PollingMode.economical.batchSize == 25)
        #expect(PollingMode.aggressive.batchSize == 200)
    }
}

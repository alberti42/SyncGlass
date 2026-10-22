import Foundation
import Testing
@testable import SyncGlass

@Suite struct PhaseTests {
    @Test func uploadedAndIdleIsCurrent() {
        #expect(ItemState().phase(trackDownloads: true) == .current)
    }

    @Test func notUploadedIsInFlight() {
        #expect(ItemState(isUploaded: false).phase(trackDownloads: false) == .inFlight(isDownload: false))
    }

    @Test func uploadingIsInFlight() {
        #expect(ItemState(isUploading: true).phase(trackDownloads: false) == .inFlight(isDownload: false))
    }

    @Test func downloadCountsOnlyWhenTracked() {
        let state = ItemState(isDownloading: true)
        #expect(state.phase(trackDownloads: true) == .inFlight(isDownload: true))
        #expect(state.phase(trackDownloads: false) == .current)
    }

    @Test func missingPathIsIgnored() {
        #expect(ItemState(exists: false, isUploaded: false).phase(trackDownloads: true) == .ignored)
    }

    /// A path outside iCloud reports no upload state, which reads as "not
    /// uploaded". It used to stay in the transfer list forever.
    @Test func pathOutsideICloudIsIgnored() {
        let state = ItemState(isUbiquitous: false, isUploaded: false)
        #expect(state.phase(trackDownloads: true) == .ignored)
    }

    @Test func containsBytes() {
        #expect(ItemState(fileSize: 1).containsBytes)
        #expect(ItemState(isDirectory: true).containsBytes)
        #expect(!ItemState(fileSize: 0).containsBytes)
    }
}

/// `ItemState(path:)` on files in a temporary folder, which is not in iCloud.
/// Each test gets its own folder; `deinit` deletes it.
@Suite final class ItemStateFileTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncGlassTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, contents: String = "abc") throws -> String {
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    @Test func regularFile() throws {
        let state = ItemState(path: try file("a.txt"))
        #expect(state.exists)
        #expect(!state.isUbiquitous)
        #expect(!state.isDirectory)
        #expect(state.fileSize == 3)
        #expect(state.containsBytes)
        #expect(state.phase(trackDownloads: true) == .ignored)
    }

    @Test func emptyFileContainsNoBytes() throws {
        #expect(!ItemState(path: try file("empty.txt", contents: "")).containsBytes)
    }

    @Test func hiddenFile() throws {
        #expect(ItemState(path: try file(".hidden")).isHidden)
    }

    @Test func directory() {
        let state = ItemState(path: folder.path)
        #expect(state.isDirectory)
        #expect(state.containsBytes)
    }

    @Test func symbolicLink() throws {
        let target = try file("target.txt")
        let link = folder.appendingPathComponent("link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        #expect(ItemState(path: link).isSymbolicLink)
    }

    @Test func missingPath() {
        let state = ItemState(path: folder.appendingPathComponent("missing").path)
        #expect(!state.exists)
        #expect(state.phase(trackDownloads: true) == .ignored)
    }
}

import Foundation
import Testing
@testable import SyncGlass

@Suite struct ICloudQueueTests {
    /// `brctl status` on macOS 27 while a 300 MB upload was stuck with Wi-Fi off,
    /// with its color codes. The first line is shortened.
    static let output = [
        "2 containers matching '*'",
        "<c{1}m.a{3}e.C{7}s[1] \u{1B}[0;1;32mforeground\u{1B}[0m {client:\u{1B}[31mneeds-sync\u{1B}[39m sync:needs-sync-up|in-sync-up|has-synced-down}>",
        "    Client Truth Unclean Items:",
        "    --------------------------",
        "    Under /",
        "        r:3389462 i:\u{1B}[33m<69AF9158>\u{1B}[39m al:1 foid:<n33b816> up:\u{1B}[31mneeds-sync-up\u{1B}[39m uv:1 mt:1792963455 st{p:\u{1B}[33m<root[1]>\u{1B}[39m n:\"\u{1B}[0;1mS{20}t\u{1B}[0m\" dir bt:1792963455 m:rw- creator:0 sc:docs}",
        "        > sync-up{[zone:1 in-flight{synced-all} \u{1B}[31msync-up-scheduled\u{1B}[39m attempts:0 last:\u{1B}[0;1;34m1.10m ago\u{1B}[0m next:\u{1B}[0;1;34mready\u{1B}[0m cleanup:\u{1B}[0;1;34m58.88m\u{1B}[0m]}",
        "    Under /SyncGlass offline test",
        "        r:3389463 i:\u{1B}[33m<816F941B>\u{1B}[39m al:1 foid:<f33b817> ld{synced-all} up:\u{1B}[31mneeds-upload\u{1B}[39m uv:1 st{p:\u{1B}[33m<69AF9158>\u{1B}[39m n:\"\u{1B}[0;1mo{10}t.bin\u{1B}[0m\" doc bt:1792963455 m:rw- creator:0 sc:docs} up-id{fid:502868389, gen:1} ct{mt:1792963456 sz:\u{1B}[0;1;30m314.6 MB (314572800)\u{1B}[0m n:\"o{10}t.bin\" sig:\u{1B}[0;1;30m<file-pending>\u{1B}[0m tsig:\u{1B}[0;1;30m<pending>\u{1B}[0m device:0}",
        "        > upload{[ \u{1B}[0;1;32mactive\u{1B}[0m attempts:0 last:\u{1B}[0;1;34m1.10m ago\u{1B}[0m next:\u{1B}[0;1;34mready\u{1B}[0m cleanup:\u{1B}[0;1;34m58.88m\u{1B}[0m]}",
        "<c{1}m.a{3}e.C{7}s:_d8348635ada49fb95e975ca14f8cc123[2] \u{1B}[0;1;30mbackground\u{1B}[0m {client:idle server:fetched-recents|fetched-favorites sync:oob-sync-ack last-sync:2025-08-08 16:45:34.162, consistent zoneActiveState:{rid:3} appuninstalled:(null)}>",
        "Desktop & Documents: current=YES lastEnabled=(never) lastDisabled=(never)",
    ].joined(separator: "\n")

    static let now = Date(timeIntervalSince1970: 1_792_963_521)

    @Test func parsesFileAndFolder() {
        let items = ICloudQueue.parse(Self.output, now: Self.now)
        #expect(items.count == 2)
        #expect(items[0] == QueueItem(
            container: "c{1}m.a{3}e.C{7}s", folder: "/", name: "S{20}t", isDirectory: true, size: nil,
            fileProviderID: "n33b816", state: "needs-sync-up",
            operation: .init(kind: "sync-up", attempts: 0, lastAttempt: Self.now.addingTimeInterval(-66))))
        #expect(items[1] == QueueItem(
            container: "c{1}m.a{3}e.C{7}s", folder: "/SyncGlass offline test", name: "o{10}t.bin",
            isDirectory: false, size: 314_572_800, fileProviderID: "f33b817", state: "needs-upload",
            operation: .init(kind: "upload", attempts: 0, lastAttempt: Self.now.addingTimeInterval(-66))))
    }

    @Test func emptyQueue() {
        let output = """
            2 containers matching '*'
            <c{1}m.a{3}e.C{7}s[1] foreground {client:idle sync:has-synced-down}>
            Desktop & Documents: current=YES lastEnabled=(never) lastDisabled=(never)
            """
        #expect(ICloudQueue.parse(output).isEmpty)
        #expect(ICloudQueue.parse("").isEmpty)
    }

    @Test func nameAbbreviations() {
        #expect(ICloudQueue.matchesAbbreviation("offline-test.bin", "o{10}t.bin"))
        #expect(ICloudQueue.matchesAbbreviation("SyncGlass offline test", "S{20}t"))
        #expect(ICloudQueue.matchesAbbreviation("Documents", "D{7}s"))
        #expect(!ICloudQueue.matchesAbbreviation("offline-test.zip", "o{10}t.bin"))
        #expect(!ICloudQueue.matchesAbbreviation("Desktop", "D{7}s"))
        #expect(ICloudQueue.matchesAbbreviation("ab", "ab"))
    }

    @Test func containerAbbreviations() {
        #expect(ICloudQueue.matchesContainer("com.apple.CloudDocs", "c{1}m.a{3}e.C{7}s"))
        #expect(!ICloudQueue.matchesContainer("com.apple.Keynote", "c{1}m.a{3}e.C{7}s"))
        #expect(!ICloudQueue.matchesContainer("com.apple", "c{1}m.a{3}e.C{7}s"))
    }

    @Test func stuckRule() {
        #expect(ICloudQueue.isStuck(hasError: true, isQueued: false, unchangedFor: 0))
        #expect(ICloudQueue.isStuck(hasError: false, isQueued: true, unchangedFor: ICloudQueue.stallTime))
        #expect(!ICloudQueue.isStuck(hasError: false, isQueued: true, unchangedFor: ICloudQueue.stallTime - 1))
        #expect(!ICloudQueue.isStuck(hasError: false, isQueued: false, unchangedFor: 3600))
    }
}

import CoreServices
import Testing
@testable import SyncGlass

@Suite struct StartEventIDTests {
    static let now = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)

    @Test func replaysFromTheSavedID() {
        #expect(Tracker.startEventID(saved: 500, current: 900) == 500)
        #expect(Tracker.startEventID(saved: 900, current: 900) == 900)
    }

    @Test func startsNowWithoutASavedID() {
        #expect(Tracker.startEventID(saved: nil, current: 900) == Self.now)
        #expect(Tracker.startEventID(saved: 0, current: 900) == Self.now)
    }

    /// An ID newer than the current one means the event database was reset.
    @Test func startsNowAfterAReset() {
        #expect(Tracker.startEventID(saved: 901, current: 900) == Self.now)
    }
}

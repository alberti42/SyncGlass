import Foundation
import Testing
@testable import SyncGlass

@Suite struct FilterTests {
    let path = "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Projects/report.tmp"

    @Test func emptyIncludeListTracksEveryPath() {
        #expect(PathChecks.passesFilters(path, includes: [], excludes: []))
    }

    @Test func pathMustMatchAnInclude() {
        #expect(PathChecks.passesFilters(path, includes: ["/Projects/"], excludes: []))
        #expect(!PathChecks.passesFilters(path, includes: ["/Photos/"], excludes: []))
    }

    @Test func excludeWinsOverInclude() {
        #expect(!PathChecks.passesFilters(path, includes: ["/Projects/"], excludes: [#"\.tmp$"#]))
    }

    @Test func patternsMatchAnywhereInTheFullPath() {
        #expect(PathChecks.matches(path, pattern: "CloudDocs"))
        #expect(PathChecks.matches(path, pattern: "^/Users/"))
        #expect(!PathChecks.matches(path, pattern: "^Projects"))
    }

    /// Desktop and Documents in iCloud are real folders in the home folder, and
    /// FSEvents reports their files there.
    @Test func defaultIncludesTrackDesktopAndDocuments() {
        let includes = Prefs.defaultIncludePatterns(home: "/Users/me")
        for path in [
            path,
            "/Users/me/Documents/report.pdf",
            "/Users/me/Desktop/Folder/photo.png",
            "/Users/me/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault/note.md",
        ] {
            #expect(PathChecks.passesFilters(path, includes: includes, excludes: []), "\(path)")
        }
        for path in [
            "/Users/me/Downloads/file.zip",
            "/Users/me/Documentsx/file.txt",
            "/Users/other/Documents/file.txt",
            "/Volumes/Disk/Users/me/Documents/file.txt",
        ] {
            #expect(!PathChecks.passesFilters(path, includes: includes, excludes: []), "\(path)")
        }
    }

    @Test func defaultIncludesEscapeTheHomeFolder() {
        let includes = Prefs.defaultIncludePatterns(home: "/Users/a.b+c")
        #expect(PathChecks.passesFilters("/Users/a.b+c/Documents/x", includes: includes, excludes: []))
        #expect(!PathChecks.passesFilters("/Users/aXbbc/Documents/x", includes: includes, excludes: []))
    }

    @Test func invalidPatternMatchesNothing() {
        #expect(!PathChecks.matches(path, pattern: "("))
        #expect(PathChecks.passesFilters(path, includes: [], excludes: ["("]))
    }
}

@Suite struct ImplicitPackageTests {
    @Test func parentFrameworkOrBundle() {
        #expect(PathChecks.isInsideImplicitPackage("/a/Foo.framework/Versions/A/Foo"))
        #expect(PathChecks.isInsideImplicitPackage("/a/Plugin.bundle/Contents/Info.plist"))
    }

    @Test func onlyParentsCount() {
        #expect(!PathChecks.isInsideImplicitPackage("/a/Foo.framework"))
        #expect(!PathChecks.isInsideImplicitPackage("/a/b/c.txt"))
    }
}

/// Decimal units, at most 2 fraction digits, in the current locale.
@Suite struct HumanReadableTests {
    let sep = Locale.current.decimalSeparator ?? "."

    @Test func bytes() {
        #expect(PathChecks.humanReadable(bytes: 0) == "0 B")
        #expect(PathChecks.humanReadable(bytes: 999) == "999 B")
    }

    @Test func decimalUnits() {
        #expect(PathChecks.humanReadable(bytes: 1000) == "1 kB")
        #expect(PathChecks.humanReadable(bytes: 2_000_000) == "2 MB")
        #expect(PathChecks.humanReadable(bytes: 3e9) == "3 GB")
    }

    @Test func atMostTwoFractionDigits() {
        #expect(PathChecks.humanReadable(bytes: 1500) == "1\(sep)5 kB")
        #expect(PathChecks.humanReadable(bytes: 209_716_000) == "209\(sep)72 MB")
    }

    @Test func largestUnitIsYottabyte() {
        #expect(PathChecks.humanReadable(bytes: 5e24) == "5 YB")
        #expect(PathChecks.humanReadable(bytes: 5e27).hasSuffix(" YB"))
    }
}

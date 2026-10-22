import Foundation

/// The iCloud and file-system state of one path, read through URL resource values.
struct ItemState {
    let exists: Bool
    let isUbiquitous: Bool
    let isUploaded: Bool
    let isUploading: Bool
    let isDownloading: Bool
    let isCurrent: Bool
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymbolicLink: Bool
    let fileSize: Int

    private static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .fileSizeKey,
    ]

    init(path: String) {
        let url = URL(fileURLWithPath: path)
        // FileManager.fileExists follows symlinks.
        exists = FileManager.default.fileExists(atPath: path)
        let v = try? url.resourceValues(forKeys: Self.keys)
        isUbiquitous = v?.isUbiquitousItem ?? false
        isUploaded = v?.ubiquitousItemIsUploaded ?? false
        isUploading = v?.ubiquitousItemIsUploading ?? false
        isDownloading = v?.ubiquitousItemIsDownloading ?? false
        isCurrent = v?.ubiquitousItemDownloadingStatus == .current
        isDirectory = v?.isDirectory ?? false
        isPackage = v?.isPackage ?? false
        isHidden = v?.isHidden ?? false
        isSymbolicLink = v?.isSymbolicLink ?? false
        fileSize = v?.fileSize ?? 0
    }

    /// A state with the given values, without reading the file system.
    init(exists: Bool = true, isUbiquitous: Bool = true, isUploaded: Bool = true, isUploading: Bool = false,
         isDownloading: Bool = false, isCurrent: Bool = true, isDirectory: Bool = false, isPackage: Bool = false,
         isHidden: Bool = false, isSymbolicLink: Bool = false, fileSize: Int = 0) {
        self.exists = exists
        self.isUbiquitous = isUbiquitous
        self.isUploaded = isUploaded
        self.isUploading = isUploading
        self.isDownloading = isDownloading
        self.isCurrent = isCurrent
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isSymbolicLink = isSymbolicLink
        self.fileSize = fileSize
    }

    /// Whether the item has content worth tracking: a non-empty file, or a folder.
    var containsBytes: Bool { fileSize != 0 || isDirectory }

    enum Phase: Equatable {
        /// The path no longer exists, or it is not in iCloud, such as a path
        /// inside a `.nosync` folder. Such a path has no upload state.
        case ignored
        /// In transfer. `isDownload` is true when the item is uploaded and downloading.
        case inFlight(isDownload: Bool)
        /// Uploaded, not uploading and (when downloads are tracked) not downloading.
        case current
    }

    /// A path stays in flight until it reports uploaded, not uploading and (when
    /// "Track incoming downloads" is on) not downloading.
    func phase(trackDownloads: Bool) -> Phase {
        guard exists, isUbiquitous else { return .ignored }
        if !isUploaded || isUploading || (trackDownloads && isDownloading) {
            return .inFlight(isDownload: isUploaded && isDownloading)
        }
        return .current
    }
}

enum PathChecks {
    /// `isTracked`: true when the folder lives in iCloud
    /// (used for Desktop and Documents when "Desktop & Documents" sync is on).
    static func isTracked(_ path: String) -> Bool {
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey])
        return v?.isUbiquitousItem ?? false
    }

    /// `isFilePackaged`: true when any parent folder is a package.
    static func isInsidePackage(_ path: String) -> Bool {
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count > 1 {
            let v = try? URL(fileURLWithPath: parent).resourceValues(forKeys: [.isPackageKey])
            if v?.isPackage == true { return true }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return false
    }

    /// `isImplicitlyPackaged`: true when a parent folder ends in `.framework` or `.bundle`.
    static func isInsideImplicitPackage(_ path: String) -> Bool {
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count > 1 {
            let ext = (parent as NSString).pathExtension
            if ext == "framework" || ext == "bundle" { return true }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return false
    }

    /// `matchesWithExpression:options:matches:` against the full path.
    static func matches(_ path: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        return re.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    /// Include/exclude filtering. A path must match an include pattern (an empty
    /// include list matches every path) and no exclude pattern.
    static func passesFilters(_ path: String) -> Bool {
        passesFilters(path, includes: Prefs.includePatterns, excludes: Prefs.excludePatterns)
    }

    static func passesFilters(_ path: String, includes: [String], excludes: [String]) -> Bool {
        if !includes.isEmpty && !includes.contains(where: { matches(path, pattern: $0) }) {
            return false
        }
        return !excludes.contains(where: { matches(path, pattern: $0) })
    }

    /// `GLOBALS.CONVERTBYTESTOHUMANREADABLE`: decimal units, at most 2 fraction digits.
    static func humanReadable(bytes: Double) -> String {
        let units = ["", "k", "M", "G", "T", "P", "E", "Z", "Y"]
        var value = bytes
        var i = 0
        while value >= 1000 && i < units.count - 1 {
            value /= 1000
            i += 1
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return "\(f.string(from: NSNumber(value: value)) ?? "0") \(units[i])B"
    }

    static func directorySize(_ path: String) -> Int {
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total = 0
        for case let url as URL in e {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

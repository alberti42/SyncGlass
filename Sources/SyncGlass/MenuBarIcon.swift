import AppKit

/// Renders the menu-bar icon.
///
/// Every image is a template image: the menu bar draws it in its own foreground
/// color, so the icon is monochrome and follows light mode, dark mode, tinted
/// wallpapers and the highlighted state. Shades come from alpha only.
@MainActor
enum MenuBarIcon {
    enum Symbol: String {
        case idle = "icloud"
        case uploading = "icloud.and.arrow.up"
        case downloading = "icloud.and.arrow.down"
        case syncing = "arrow.clockwise.icloud"
        case offline = "icloud.slash"
        /// Watch for Stuck Files found a stuck file.
        case stuck = "exclamationmark.icloud"
    }

    private static let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)

    /// Offline wins over stuck: it explains why transfers stall.
    static func symbol(for snapshot: TrackerSnapshot, isReachable: Bool, stuckCount: Int = 0) -> Symbol {
        guard isReachable else { return .offline }
        if stuckCount > 0 { return .stuck }
        switch snapshot.status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .transferring: return snapshot.isDownloadingOnly ? .downloading : .uploading
        }
    }

    static func image(for snapshot: TrackerSnapshot, isReachable: Bool, showsProgress: Bool,
                      stuckCount: Int = 0) -> NSImage {
        let symbol = symbol(for: snapshot, isReachable: isReachable, stuckCount: stuckCount)
        let image: NSImage
        if showsProgress && symbol != .stuck && isReachable && snapshot.status == .transferring
            && snapshot.totalTransferCount > 1
        {
            image = progressImage(progress: snapshot.progress)
        } else {
            image = symbolImage(symbol.rawValue)
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel(for: snapshot, isReachable: isReachable,
                                                            stuckCount: stuckCount)
        return image
    }

    static func accessibilityLabel(for snapshot: TrackerSnapshot, isReachable: Bool, stuckCount: Int = 0) -> String {
        guard isReachable else { return "SyncGlass: offline" }
        if stuckCount > 0 { return "SyncGlass: \(stuckCount) stuck \(stuckCount == 1 ? "file" : "files")" }
        return "SyncGlass: \(StatusModel.detailText(for: snapshot))"
    }

    private static func symbolImage(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        return image
    }

    /// A cloud outline that fills from left to right as transfers complete.
    private static func progressImage(progress: Double) -> NSImage {
        let outline = symbolImage("icloud")
        let filled = symbolImage("icloud.fill")
        let size = outline.size
        return NSImage(size: size, flipped: false) { rect in
            outline.draw(in: rect)
            let clip = NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height)
            NSGraphicsContext.saveGraphicsState()
            clip.clip()
            filled.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
}

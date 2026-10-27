# Changelog

All notable changes to SyncGlass are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-10-27

### Added

- Watch for Stuck Files in the panel's ⋯ menu, off by default. While it is on, SyncGlass reads iCloud Drive's queue with `brctl status` every minute. A bar below the panel's header shows when SyncGlass last checked and how many files are stuck; its ⓘ button explains the watch and how to report a stuck file. The menu-bar icon shows a cloud with an exclamation mark while a file is stuck. Files that iCloud has not synced appear in Transfers, stuck files first. A file is marked stuck ("Waiting · last attempt 4 min ago") when iCloud reports an upload or download error for it, or when it is in iCloud's queue and its upload has not progressed for 2 minutes. File Info shows the file's entry in the queue.
- `--queue-status` prints iCloud Drive's queue with the files it refers to, and exits.
- A Troubleshooting section in the README: what SyncGlass does not do, and how to read iCloud Drive's log.

### Changed

- Transfers that were running when SyncGlass quit, or that started while it was not running, appear in Transfers after the next launch. SyncGlass saves the files in transfer and asks macOS (FSEvents) for the changes made since it last ran. Scan for Transfers is rarely needed and has moved from the panel's ⋯ menu to Settings > Monitoring only.
- Scan for Transfers also finds files that are downloading, and adds the files it finds to Transfers instead of replacing the list.
- Settings has a Monitoring tab with the folder, the check frequency, hidden files, symbolic links and Scan for Transfers. General keeps the menu bar, startup and updates.

## [0.2.1] - 2026-10-24

### Changed

- The panel's gear button opens SyncGlass's Settings. The button that opens iCloud's page in System Settings shows a cloud.

## [0.2.0] - 2026-10-24

### Added

- Software updates through [Sparkle](https://sparkle-project.org). SyncGlass checks for a new version once a week. The welcome screen and Settings > General turn the weekly check on or off; Check for Updates in the panel's menu checks at once. When the weekly check finds an update, the menu item reads "Update to X.Y.Z…" until you open it.

## [0.1.0] - 2026-10-22

### Added

- Menu-bar icon that shows whether iCloud Drive is idle, uploading, downloading or syncing changes from other devices. The icon is monochrome and follows light and dark mode. An optional mode fills the cloud as files finish.
- Panel with the files in transfer and the recently transferred files. Each file in transfer shows its upload or download percentage, read from the progress that iCloud Drive publishes. Each recent file shows when its transfer finished.
- File Info window with the iCloud state of a file (status, live percentage, conflicts, errors, sharing), its last recorded transfer, and every date macOS keeps for it.
- Notifications when uploads or downloads finish, with a minimum transfer time and a choice of sound.
- Include and exclude filters as regular expressions matched against the full path.
- Scan for Transfers, which finds files that started uploading before SyncGlass was running.
- History log of finished transfers.
- Open at login through a login helper registered with `SMAppService`.
- App icon: a magnifying glass over a half-filled cloud.

[Unreleased]: https://github.com/alberti42/SyncGlass/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/alberti42/SyncGlass/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/alberti42/SyncGlass/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/alberti42/SyncGlass/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/alberti42/SyncGlass/releases/tag/v0.1.0

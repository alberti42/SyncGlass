# Changelog

All notable changes to SyncGlass are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- App icon: a magnifying glass over a half-filled cloud.

### Fixed

- Files that are not in iCloud, such as files inside a `.nosync` folder, were listed as uploading and never finished. The tracker and Scan for Transfers now skip them.

## [0.1.0] - 2026-10-20

### Added

- Menu-bar icon that shows whether iCloud Drive is idle, uploading, downloading or syncing changes from other devices. The icon is monochrome and follows light and dark mode. An optional mode fills the cloud as files finish.
- Panel with the files in transfer and the recently transferred files. Each file in transfer shows its upload or download percentage, read from the progress that iCloud Drive publishes. Each recent file shows when its transfer finished.
- File Info window with the iCloud state of a file (status, live percentage, conflicts, errors, sharing), its last recorded transfer, and every date macOS keeps for it.
- Notifications when uploads or downloads finish, with a minimum transfer time and a choice of sound.
- Include and exclude filters as regular expressions matched against the full path.
- Scan for Transfers, which finds files that started uploading before SyncGlass was running.
- History log of finished transfers.
- Open at login through a login helper registered with `SMAppService`.

[Unreleased]: https://github.com/alberti42/SyncGlass/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alberti42/SyncGlass/releases/tag/v0.1.0

# Security Policy

## Supported versions

Only the latest release receives fixes. SyncGlass updates itself through Sparkle, so a fix reaches users with the next release.

## Reporting a vulnerability

Report a vulnerability privately through GitHub: open the [Security tab](https://github.com/alberti42/SyncGlass/security) of this repository and choose **Report a vulnerability**. Do not open a public issue for a vulnerability.

Include the SyncGlass version (About SyncGlass in the panel's menu), the macOS version, and the steps to reproduce the problem.

## What SyncGlass does that matters for security

- In the folder you choose (`~/Library/Mobile Documents`, or its iCloud Drive part), it reads file names, sizes, dates and iCloud state. It does not read file contents.
- While Watch for Stuck Files is on, it runs `/usr/bin/brctl status` every minute. `brctl` lists the items iCloud Drive has not synced yet; it runs on your Mac and sends nothing to the network.
- It connects to the network only for updates: it downloads `Releases/appcast.xml` from this repository and, when you install an update, `SyncGlass.zip` from GitHub Releases. Sparkle installs an update only if the ZIP's EdDSA signature matches the public key in the app.
- Each release ZIP is built by GitHub Actions from the tagged source, signed with a Developer ID, notarized by Apple, and carries a build provenance attestation. To check where a downloaded ZIP was built:

  ```sh
  gh attestation verify SyncGlass.zip --repo alberti42/SyncGlass
  ```

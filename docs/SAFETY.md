# Safety, coverage, and privacy

Klearspace runs as your user. It does not invoke the original shell script, request administrator credentials, install a privileged helper, empty Trash, or remove system folders. Scans inspect directory metadata, application bundle metadata and code-signing entitlements, container metadata plists, and running-process names. They do not read personal documents to calculate their sizes.

## Cleanup safeguards

- Exact allowed cleanup locations inside your home folder.
- Protection for whole Library roots, Apple data, Klearspace's own bundle IDs, running apps/tools, and shared group containers.
- Symbolic-link targets excluded; size enumeration does not follow symlinks into other directories.
- Identity and modification-time checks against scan results before each move.
- Partially scanned or inaccessible items excluded from cleanup.
- Parent/child overlap removal to prevent duplicate counting and moves.
- Explicit review of all selected paths, plus an acknowledgement for app leftovers.
- Native macOS Trash moves with recovery history, followed by restore identity and overwrite checks.

These safeguards reduce common cleanup risks. There is no claim to detect every background process, every installation location, or every concurrent filesystem change. Close related applications and review the paths before cleaning.

## Coverage

| Category | Recognized locations |
| --- | --- |
| Developer | Xcode Derived Data/cache, Gradle cache, npm `_cacache`, Yarn caches, pnpm cache, Homebrew downloads, CocoaPods cache, pip caches, SwiftPM caches, Cargo registry downloads, Flutter/Dart hosted downloads and Git download cache, JetBrains/Android Studio caches, VS Code cache folders |
| Applications | Eligible entries in `~/Library/Caches`; Apple service caches remain protected |
| Browsers | Chrome, Edge and Brave profile cache subfolders; Firefox disk cache; recognized Safari and Chromium user Library cache folders |
| Logs | Individual files in `~/Library/Logs` last modified more than 30 days ago |
| Leftovers | Bundle-ID candidates in Containers, Application Scripts, Application Support, Preferences, Saved Application State, HTTPStorages and WebKit; exact named support folders from previously seen apps |

## Exclusions and limitations

No automatic removal of simulator devices, iOS DeviceSupport, editor workspace storage, CocoaPods repositories, pnpm's linked package store, browser passwords/cookies/history/bookmarks, user documents outside reviewed containers/support folders, system caches/logs, launch agents, privileged daemons, system extensions, Keychain entries, or cloud data.

Unknown support-folder names cannot reliably be mapped to removed apps. Disconnected drives and custom app locations may cause false leftover candidates. Containers can contain valuable personal data. Shared containers remain protected even if no owner is found.

Apple documents how [app groups share containers](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups) and how [macOS protects access to app containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers). Prefer a vendor's official uninstaller when available; see [Apple's uninstall guidance](https://support.apple.com/102610).

## Local state

| Location | Purpose |
| --- | --- |
| `~/Library/Application Support/Klearspace/history.json` | Cleanup time, original/Trash paths, file identity, size, and restore status |
| `~/Library/Application Support/Klearspace/known-apps.json` | App bundle identifiers and exact app names seen during scans |
| App preferences | System/Light/Dark appearance choice |

No telemetry, ads, update checker, external analytics, or third-party runtime packages are included. Exporting a report writes a local JSON file selected by you. GitHub is contacted only when you visit project links or download a release yourself.

For reporting a potential safety issue, see [SECURITY.md](../SECURITY.md).

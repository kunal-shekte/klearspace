# Use Klearspace

## 1. Scan your Mac

Click **Scan my Mac**, or press **⌘R**. The scan measures known cleanup locations and checks installed and running apps. It does not move or delete cleanup targets. It stores a small local catalogue of application names to improve detection after future uninstalls.

The progress message identifies the area being scanned. You can cancel. Cancelled scans show partial results with nothing selected automatically.

## 2. Review the results

Overview shows the total size of eligible data, category totals, protected items, and file locations. The ring compares eligible bytes with all bytes found in the scan. The storage card shows your Mac's available disk capacity.

Choose a category in the sidebar, or click its card. Filter results by name or path. Click a result's name or chevron for its explanation, file count, scan status, and **Reveal in Finder** action.

| Label | Meaning |
| --- | --- |
| Rebuildable | Recognized cache data or logs eligible for the recommended selection. Recreating caches can make the next build or launch slower. |
| Review first | Data that needs an explicit decision, including possible app leftovers and Flutter/Dart package downloads. |
| Protected | Running app/tool data, Apple service caches, or shared containers excluded from cleanup. |
| Incomplete | Not all data could be read, or a scan limit was reached. The size is a lower bound and the item cannot be selected. |

**Recommended** selects eligible rebuildable results across the scan. **Clear selection** clears the current selection across categories. Selections remain visible in the bottom bar as you switch categories.

## 3. Clean caches and old logs

1. Quit the apps and build tools whose caches you want to clean.
2. Scan again so running-app protections and sizes are current.
3. Review the selected results and deselect anything you want to keep.
4. Click **Review cleanup**.
5. Check the exact paths in the review sheet.
6. Click **Move selected to Trash** to perform one batch cleanup.

The engine rechecks paths, file identity, modification dates, running apps/tools, and installed-app ownership before moving anything. Changed or inaccessible items are skipped and reported. A scan recommendation is not a guarantee that no background helper can access a file; close related apps before proceeding.

Cache cleanup can require downloads or rebuilds afterward. Old logs can help diagnose past problems. Flutter/Dart package downloads require a later `flutter pub get` or `dart pub get` in affected projects; offline builds may fail until dependencies are downloaded again.

## 4. Review data left after an uninstall

Open **App leftovers**. The app looks for bundle-identifier matches in user containers, preferences, support files, application scripts, saved state, HTTPStorages, and WebKit. Apps seen in earlier scans can also be matched to named support folders.

No matching app means **possible leftover**, not proven abandoned data. Apps on disconnected disks, custom install locations, command-line programs, and helper services may still own it. Containers can hold documents, databases, settings, or downloaded content.

1. Expand candidates and reveal unfamiliar locations in Finder.
2. Select individual results, or use **Select candidates** to select every eligible result currently visible in this category. An active text filter limits that selection.
3. Click **Review cleanup** and check the final list, which also includes selections from other categories.
4. Acknowledge that you reviewed the selected app data.
5. Click **Move selected to Trash** for one batch removal.

Shared group containers stay protected because more than one app can use them. Klearspace does not remove privileged services, system extensions, cloud data, or Keychain items. Use the vendor's official uninstaller for apps with services and extensions. See [safety and coverage](SAFETY.md).

## 5. Recover an item

Open **Activity** and choose **Restore** beside an item. Restore verifies the identity of the trashed item and refuses to overwrite an existing destination. If an app has already recreated the original folder, choose **Reveal in Trash** and restore or merge the files manually with Finder.

Recovery is available only while those files remain in Trash. Items manually changed in Trash may require manual restoration. The app cannot recover files after Trash has been emptied.

## 6. Reclaim disk space

Moving files to Trash preserves recovery and generally does not immediately free storage. When you are satisfied with the cleanup, empty Trash using Finder yourself. Klearspace never empties it automatically.

Reported sizes are allocated-byte estimates. APFS clones, snapshots, hard links, open file handles, and newly recreated caches can cause physical disk-space changes to differ from the estimate.

## Appearance and reports

Use the top-bar appearance menu or **Settings → Appearance** for **System**, **Light**, and **Dark**. System is the initial default. This changes only Klearspace's appearance.

Use **Settings → Scan report → Export scan report** to save results as JSON. Reports contain local file paths; review them before sharing. Nothing is uploaded automatically.

## Troubleshooting

| Situation | Next step |
| --- | --- |
| Item is protected because an app is running | Quit the app or build tool and scan again. |
| Permission or incomplete-scan note | Review the note; optionally grant access as described in the [installation guide](INSTALLATION.md). |
| File changed since scanning | Scan again; the app intentionally refuses stale targets. |
| Disk capacity did not increase | Items may still be in Trash, recreated by apps, or retained by APFS snapshots. |
| Restore says the original path exists | Reveal the item in Trash and restore manually without overwriting new data. |
| SAMPLE DATA label is visible | You launched with `--demo`. Quit and reopen normally to scan real data. Cleanup is disabled in demo mode. |

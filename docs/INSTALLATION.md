# Install Klearspace

## Requirements

- An Apple silicon Mac (M1 or newer) for the published `arm64` DMG.
- macOS 14 Sonoma or later.
- No subscription, account, or network connection is required to scan or clean.

Intel Macs can build the source with Swift 6 or newer; the downloadable v1.1.0 binary is Apple silicon only.

## Download and install

1. Download [Klearspace 1.1.0 for Apple silicon](https://github.com/kunal-shekte/klearspace/releases/download/v1.1.0/Klearspace-1.1.0-arm64.dmg) from the project's [GitHub Releases](https://github.com/kunal-shekte/klearspace/releases).
2. Double-click the DMG to mount it.
3. Drag **Klearspace.app** onto the **Applications** shortcut in the mounted image.
4. Eject the mounted Klearspace disk image.
5. Open **Applications → Klearspace**.

There is no installer package, privileged helper, launch agent, or background service. Installation does not start a scan or clean anything.

### First launch and signing

Version 1.1.0 is an **ad-hoc-signed community build**. It is not signed with an Apple Developer ID distribution certificate or notarized by Apple. A downloaded copy may be blocked by Gatekeeper.

Review the repository and release before deciding to open it. If macOS blocks a copy you trust, use Apple's documented per-app approval flow in **System Settings → Privacy & Security → Open Anyway** after attempting to launch it. See [Apple: Open apps safely on your Mac](https://support.apple.com/102445). Your device's policy may prevent this option; building the source locally is an alternative.

Do not turn off Gatekeeper, disable System Integrity Protection, or remove quarantine flags globally. If macOS reports malware or a damaged application, stop and verify the download instead of forcing it to launch.

### Verify the download

Download `SHA256SUMS.txt` from the same release, place it beside the DMG, then run:

```sh
cd ~/Downloads
shasum -a 256 -c SHA256SUMS.txt
```

The filename must match the release asset exactly. You should see `Klearspace-1.1.0-arm64.dmg: OK`. This verifies file integrity against the release checksum; it does not replace Apple's notarization or independent review.

## Optional access to protected folders

Start with a normal scan. If scan notes report permission errors and you want those locations included:

1. In Klearspace, open **Settings → Access → Open privacy settings**.
2. In **Privacy & Security → Full Disk Access**, add the installed **Applications/Klearspace.app** and enable it.
3. Quit Klearspace with **⌘Q** and reopen it.
4. Scan again.

Access is optional. Unreadable or partially scanned results are excluded from cleanup. macOS may still protect some app containers. Never grant Terminal Full Disk Access just to use Klearspace.

## Set the appearance

The default is **System**, which follows your Mac's light or dark appearance. Use the appearance menu in the top bar, or **Settings → Appearance**, to choose **System**, **Light**, or **Dark**. Your choice survives relaunches.

## Update

Quit Klearspace, download a newer release, and replace the old app in Applications. Local cleanup history and app-name history stay in your user Library. Appearance preferences also stay saved. A new ad-hoc signature may require you to regrant optional Full Disk Access.

If you used the earlier Clearspace preview, quit and remove that old app separately. The renamed app has its own bundle identifier and support folder; the preview's state is not silently moved or deleted. Any preview items already in Trash can still be restored with Finder.

## Uninstall

Quit the app and move **Applications/Klearspace.app** to Trash. To remove Klearspace's own local state as well, review and remove these exact locations in Finder:

- `~/Library/Application Support/Klearspace/` — cleanup history and the app-name catalogue.
- `~/Library/Preferences/io.github.kunal-shekte.klearspace.plist` — preferences, including appearance.
- `~/Library/Saved Application State/io.github.kunal-shekte.klearspace.savedState/` — if present.

Removing history does not restore items previously moved to Trash. Restore anything you need first. The app installs no background components.

For the day-to-day workflow, see the [usage guide](USAGE.md).

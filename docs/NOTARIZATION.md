# Developer ID signing and notarization

This is the release procedure for a future notarized Klearspace build. **The published v1.1.0 DMG remains ad-hoc signed and is not notarized.** Adding scripts does not change that download or establish Apple's approval.

## Prerequisites belonging to the publisher

Use the Apple developer account whose legal identity should appear as the publisher. A company account should be used only with that company's authorization for this product. The pipeline requires an explicit Team ID; it never selects a team or a certificate automatically.

1. Your own [Apple Developer Program membership](https://developer.apple.com/programs/enroll/). A free Personal Team or Apple Development certificate is insufficient for this distribution workflow.
2. A **Developer ID Application** certificate with its private key available in your local Keychain. Create it using your own account in Xcode's account/certificate settings or [Apple's certificate portal](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/). Apple documents the required account role on that page. An Apple Development, Apple Distribution, or Developer ID Installer certificate does not replace Developer ID Application for signing this app.
3. A notarization credential profile for the same publishing team, saved in the local Keychain.
4. Xcode command-line tools and Python 3.9 or later. These release scripts use Python's standard library; the shipped app does not require Python.

Perform enrollment, purchases, agreements, Apple Account sign-in, and password entry yourself. Do not send passwords, signing private keys, `.p12` exports, or API keys in chat, issues, or pull requests.

## Save notarization credentials locally

Create an app-specific password for your publishing Apple Account through Apple's account settings, then run this in your own Terminal. Replace the two placeholders with your account and Team ID:

```sh
xcrun notarytool store-credentials Klearspace-personal-notary \
  --apple-id 'YOUR_PERSONAL_APPLE_ID' \
  --team-id 'YOUR_TEAM_ID'
```

`notarytool` securely prompts for the app-specific password and validates the credentials before storing them. The scripts receive only the profile name. You can alternatively configure a profile yourself using the App Store Connect API-key options documented by `xcrun notarytool store-credentials --help`.

List available signing identities without exporting private keys:

```sh
security find-identity -v -p codesigning
```

Identify your **Developer ID Application** entry. Set the certificate's exact name or SHA-1 and its own 10-character Team ID explicitly:

```sh
export KLEARSPACE_SIGNING_IDENTITY='Developer ID Application: YOUR_NAME (YOUR_TEAM_ID)'
export KLEARSPACE_TEAM_ID='YOUR_TEAM_ID'
```

Those values identify a certificate; they are not private-key material. Never select an employer/client identity for a personal release without authorization. A valid private key must remain in Keychain for `codesign` to work.

## Create and verify the signed distribution

Before publishing a new binary, update `VERSION` and the version text in the UI/documentation, run the tests, and commit the source. Use a new release version rather than replacing the existing public v1.1.0 asset silently.

From a clean checkout:

```sh
python3 -m unittest discover -s scripts/tests -v
swift test
python3 scripts/notarize.py \
  --profile Klearspace-personal-notary \
  --output dist/notarized
```

The pipeline:

1. Resolves a valid Developer ID Application identity for the explicitly selected Team ID and validates the named Keychain profile.
2. Builds the app, signs it with a secure timestamp and hardened runtime, and checks the signature, team, and absence of a debugging entitlement. Klearspace needs no additional hardened-runtime exceptions.
3. Uploads a ZIP containing the signed app to Apple's notary service and records the submission ID.
4. After Apple reports **Accepted**, fetches the notary log, staples and validates the app ticket, and assesses the app with Gatekeeper.
5. Packages that stapled app in a DMG, signs the DMG with the same Developer ID, and submits the DMG to Apple.
6. After the DMG is **Accepted**, staples and validates its ticket, checks its signature, runs Gatekeeper's disk-image assessment, and verifies the disk image.
7. Writes `SHA256SUMS.txt` using the **final stapled bytes**. It does not create or modify a GitHub release.

Submission records and logs live in `<output>/.notarization/`, which is ignored by Git. Inspect both `app-log.json` and `dmg-log.json`, including warnings, before distributing a release.

### Pending submissions and safe recovery

Apple may continue processing after a command returns. Exit code **2** means a submission is still **In Progress**. Rerun the same command later; saved IDs prevent duplicate uploads. Exit code **0** is produced only after both acceptance/ticket checks and the final assessments succeed. Other nonzero exits indicate failure or a prerequisite problem.

If an upload was interrupted before its ID could be saved, the script refuses to upload it again automatically. Inspect your own account's submission history:

```sh
xcrun notarytool history --keychain-profile Klearspace-personal-notary
```

After identifying the correct submission for those exact bytes, resume with `--recover-app-id UUID` or `--recover-dmg-id UUID`. Do not guess IDs or take them from a different release. A changed archive or disk image is rejected. Changes to the source commit, version, signing identity, team, or profile require a fresh output directory.

Ticket publication can lag behind acceptance. If `stapler` temporarily fails, rerun the same command later. Signing, stapling, or repackaging after checksumming changes the distributed bytes; the pipeline recalculates the checksum only after its final checks.

## Publish only after validation

Confirm the pipeline exits 0, review the notary logs, and test the downloaded app on a Gatekeeper-enabled Mac, preferably one without your development environment. Keep Gatekeeper and SIP enabled. Verify a download's checksum against the final release checksum.

Create a new GitHub tag/release containing only the verified final DMG and its final checksum. Update the public installation guide and signing-status notice to match the actual new release. Retain the accurate status of older releases. The scripts deliberately do not upload release assets or change old tags.

Developer ID plus notarization addresses the **unidentified-developer** block. macOS can still show its normal first-launch confirmation for software downloaded from the internet, or block an app for other security or device-management reasons. Notarization does not guarantee that all future systems or policies will accept a binary.

## Signing-only commands

With the same explicit identity and Team ID set, `./build.sh` signs the app, and `./scripts/package-dmg.sh` signs the DMG. These individual commands do **not** notarize or staple tickets. Without a signing identity, they retain the ad-hoc local-development behavior used by CI.

## Apple references

- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

# Contributing

Open an issue for a reproducible bug or a proposed cleanup location. Do not attach private scan reports or unredacted file paths. Changes that expand deletion scope should explain ownership evidence, running-app behavior, rebuild/recovery steps, and why the location is appropriate.

## Development

On a Mac with Swift 6 or newer:

```sh
git clone https://github.com/kunal-shekte/klearspace.git
cd klearspace
swift test
./build.sh
open dist/Klearspace.app --args --demo
```

Demo mode shows sample data and disables cleanup/restore. Test fixtures live in newly generated temporary directories. One integration test moves its own generated fixture through macOS Trash and immediately restores it. Tests do not remove pre-existing user files.

For a real scan, quit the demo and launch the built app normally. Avoid cleaning personal data during development. Verify both Light and Dark appearance, System following behavior, and persistence after relaunch when changing UI appearance.

## Packaging

```sh
./build.sh
./scripts/package-dmg.sh
```

Outputs go to `dist/` and are ignored by Git. `KLEARSPACE_BUILD_DIR` controls intermediate build placement, and `KLEARSPACE_OUTPUT_DIR` controls app/DMG output placement. Both build and package scripts accept the output override.

Packaging detects the executable's architecture for the DMG filename and generates `SHA256SUMS.txt`. A signed build requires both `KLEARSPACE_SIGNING_IDENTITY` and `KLEARSPACE_TEAM_ID`, and validates a matching **Developer ID Application** identity before building. For the full app + DMG submission, stapling, verification, and resume workflow, follow [Developer ID signing and notarization](docs/NOTARIZATION.md). Merely setting a signing identity does not notarize the app. Never commit certificates, credentials, signing profiles, user history, or scan reports.

## Pull requests

Keep changes focused and describe behavior and relevant validation. Cleanup-policy changes need meaningful fixture tests that cover both an eligible target and protected neighboring data. All contributions are made under this repository's MIT license. No CLA is required.

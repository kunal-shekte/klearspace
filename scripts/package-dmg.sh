#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

signing_identity="${KLEARSPACE_SIGNING_IDENTITY:--}"
if [ "$signing_identity" != "-" ]; then
    signing_identity="$(python3 scripts/signing.py identity)"
fi

output_dir="${KLEARSPACE_OUTPUT_DIR:-dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
version="$(cat VERSION)"
app_path="$output_dir/Klearspace.app"
if [ ! -d "$app_path" ]; then
    echo "Build the app first with ./build.sh" >&2
    exit 1
fi
codesign --verify --deep --strict "$app_path"
if [ "$signing_identity" != "-" ]; then
    python3 scripts/signing.py verify "$app_path"
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/klearspace-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_path" "$stage/Klearspace.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp docs/INSTALLATION.md "$stage/Installation.md"
cp docs/USAGE.md "$stage/Usage.md"
architecture="$(lipo -archs "$app_path/Contents/MacOS/Klearspace")"
case "$architecture" in
    arm64|x86_64) ;;
    *) architecture="universal" ;;
esac
dmg="$output_dir/Klearspace-$version-$architecture.dmg"
hdiutil create -volname Klearspace -srcfolder "$stage" -ov -format UDZO "$dmg"
if [ "$signing_identity" != "-" ]; then
    codesign --force --timestamp --sign "$signing_identity" --identifier io.github.kunal-shekte.klearspace.dmg "$dmg"
    python3 scripts/signing.py verify --disk-image "$dmg"
fi
hdiutil verify "$dmg"
(
    cd "$output_dir"
    shasum -a 256 "$(basename "$dmg")" > SHA256SUMS.txt
)
echo "Packaged: $dmg"

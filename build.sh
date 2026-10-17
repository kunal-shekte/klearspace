#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

build_dir="${KLEARSPACE_BUILD_DIR:-.build}"
output_dir="${KLEARSPACE_OUTPUT_DIR:-dist}"
mkdir -p "$build_dir" "$output_dir"
build_dir="$(cd "$build_dir" && pwd)"
output_dir="$(cd "$output_dir" && pwd)"
version="$(cat VERSION)"
swift build --scratch-path "$build_dir" -c release
swift scripts/icon.swift "$build_dir"
iconutil -c icns "$build_dir/Klearspace.iconset" -o "$build_dir/Klearspace.icns"

app_path="$output_dir/Klearspace.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$build_dir/release/Klearspace" "$app_path/Contents/MacOS/Klearspace"
cp "$build_dir/Klearspace.icns" "$app_path/Contents/Resources/Klearspace.icns"
cp LICENSE "$app_path/Contents/Resources/LICENSE"
cp NOTICE "$app_path/Contents/Resources/NOTICE"
cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Klearspace</string>
  <key>CFBundleDisplayName</key><string>Klearspace</string>
  <key>CFBundleIdentifier</key><string>io.github.kunal-shekte.klearspace</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleExecutable</key><string>Klearspace</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Klearspace.icns</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Kunal Shekte. MIT License.</string>
</dict></plist>
PLIST
printf 'APPL????' > "$app_path/Contents/PkgInfo"
signing_identity="${KLEARSPACE_SIGNING_IDENTITY:--}"
if [ "$signing_identity" = "-" ]; then
    codesign --force --deep --sign - --identifier io.github.kunal-shekte.klearspace "$app_path"
else
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_path"
fi
codesign --verify --deep --strict "$app_path"
echo "Built: $app_path"

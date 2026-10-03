#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
help=$(swift build --help)
debug_flag=-debug-info-format
if [[ "$help" == *'  --debug-info-format '* ]]; then debug_flag=--debug-info-format; fi
./scripts/swift.sh build -c release --product Dayfolio "$debug_flag" none
bin=$(./scripts/swift.sh build -c release --show-bin-path | tail -1)
app="dist/Dayfolio.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Dayfolio" "$app/Contents/MacOS/Dayfolio"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.dayfolio.diary</string>
<key>CFBundleName</key><string>Dayfolio</string>
<key>CFBundleDisplayName</key><string>拾光日记 Dayfolio</string>
<key>CFBundleExecutable</key><string>Dayfolio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Dayfolio contributors</string>
</dict></plist>
PLIST
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$app/Contents/Resources/"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$app/Contents/Info.plist"
fi
codesign --force --deep --sign - "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Dayfolio-macOS-$(uname -m).zip"
printf '%s\n' "$PWD/$app"

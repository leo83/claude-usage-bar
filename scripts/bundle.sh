#!/usr/bin/env bash
# Assembles a minimal .app bundle around the release binary and ad-hoc signs it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="ClaudeUsageTray"
APP="$ROOT/.build/$NAME.app"

# Build each slice separately, then lipo into a universal binary. (Passing two
# --arch flags at once needs full Xcode's xcbuild; separate builds work with
# just the Command Line Tools.)
swift build -c release --arch arm64
ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$NAME"
swift build -c release --arch x86_64
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/$NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>ClaudeUsageTray</string>
    <key>CFBundleDisplayName</key>     <string>Claude Usage</string>
    <key>CFBundleIdentifier</key>      <string>com.levragulin.claude-usage-tray</string>
    <key>CFBundleExecutable</key>      <string>ClaudeUsageTray</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Personal tool</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (required for SMAppService login-item registration).
codesign --force --deep --sign - "$APP"

echo "Готово: $APP"

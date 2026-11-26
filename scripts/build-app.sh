#!/usr/bin/env bash
# Builds build/Skillbook.app with only the Command Line Tools (no Xcode needed).
#   scripts/build-app.sh            build
#   scripts/build-app.sh --install  build, copy to ~/Applications and launch
#   scripts/build-app.sh --zip      build and zip it for a GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK needs SwiftUI's macro plugin, which ships only with Xcode.
# Use the newest SDK that builds without it unless SDK is set.
if [[ -z "${SDK:-}" ]]; then
  if [[ "$(xcode-select -p 2>/dev/null || true)" == *CommandLineTools* ]]; then
    SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)"
  fi
  # Full Xcode (including GitHub's macOS runners) ships the macro plugin, so its default SDK works.
  SDK="${SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
fi
ARCH="$(uname -m)"
APP=build/Skillbook.app

echo "▸ Compiling ($ARCH, $(basename "$SDK"))"
mkdir -p build
swiftc -sdk "$SDK" -target "$ARCH-apple-macos15.0" -parse-as-library -swift-version 5 -O \
  -o build/Skillbook $(find Sources -name '*.swift')

if [[ ! -f build/AppIcon.icns || assets/icon.svg -nt build/AppIcon.icns ]]; then
  echo "▸ Rendering icon"
  rm -rf build/AppIcon.iconset
  swift -sdk "$SDK" scripts/make-icon.swift assets/icon.svg build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

echo "▸ Bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Skillbook "$APP/Contents/MacOS/Skillbook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Skillbook 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Skillbook.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Skillbook.app
  echo "✓ Installed to ~/Applications and launched — look for the book icon in the menu bar"
fi

if [[ "${1:-}" == "--zip" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
  ZIP="build/Skillbook-$VERSION-mac-$ARCH.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "✓ Zipped $ZIP (attach it to a GitHub release; the site's download button finds it)"
fi

#!/bin/sh
set -eu
cd "$(dirname "$0")"
bundle='build/Quiet Desktop.app'
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" build/module-cache
xcrun swiftc main.swift -o "$bundle/Contents/MacOS/QuietDesktop" \
  -module-cache-path build/module-cache -target "$(uname -m)-apple-macosx14.0" \
  -framework SwiftUI -framework AppKit -framework PhotosUI
cp Info.plist "$bundle/Contents/Info.plist"
cp AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
xattr -cr "$bundle"
codesign --force --sign - "$bundle"
xattr -cr "$bundle"
codesign --verify --deep --strict "$bundle"
ditto -c -k --norsrc --keepParent "$bundle" 'build/Quiet Desktop.zip'
echo 'Built build/Quiet Desktop.app and build/Quiet Desktop.zip'

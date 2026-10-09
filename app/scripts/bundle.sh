#!/usr/bin/env bash
# Builds "CC Email.app" in app/build/. Pass --install to also copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

sdk="$(scripts/sdk.sh)"
if [[ -n "$sdk" ]]; then export SDKROOT="$sdk"; fi

swift build -c release --arch arm64

app="build/CC Email.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/CCEmail" "$app/Contents/MacOS/CCEmail"

plist="$app/Contents/Info.plist"
cp Resources/Info.plist "$plist"
version="$(git describe --tags --abbrev=0 2>/dev/null || echo 0.1)"
plutil -replace CFBundleIdentifier -string "${BUNDLE_ID:-com.example.ccemail}" "$plist"
plutil -replace CFBundleShortVersionString -string "${version#v}" "$plist"

if [[ -f Resources/AppIcon.png ]]; then
    iconset="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z $size $size Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
    plutil -replace CFBundleIconFile -string AppIcon "$plist"
fi

# Ad-hoc signature. No sandbox: the app has to start `claude` and read the workspace.
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/CC Email.app"
    cp -R "$app" "$HOME/Applications/"
    echo "Installed to ~/Applications/CC Email.app"
fi

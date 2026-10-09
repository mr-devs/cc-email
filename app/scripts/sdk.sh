#!/usr/bin/env bash
# Prints the macOS SDK path to build with, or nothing to use the default.
#
# Newer SDKs (macOS 27+) implement SwiftUI's @State as a macro whose compiler plugin
# ships only with Xcode. With just the Command Line Tools, pick the newest installed SDK
# whose SwiftUI doesn't make @State a macro.
set -euo pipefail

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -n "$developer_dir" ]] && find "$developer_dir" -path "*host/plugins*" -name "*SwiftUIMacros*" -print -quit 2>/dev/null | grep -q .; then
    exit 0  # Xcode is selected and has the plugin: the default SDK works.
fi

sdks_dir="${developer_dir:-/Library/Developer/CommandLineTools}/SDKs"
[[ -d "$sdks_dir" ]] || sdks_dir="/Library/Developer/CommandLineTools/SDKs"

# Real SDK directories (not symlinks), newest version first.
for sdk in $(find "$sdks_dir" -maxdepth 1 -type d -name 'MacOSX[0-9]*.sdk' | sort -t X -k 2 -V -r); do
    interface="$sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
    if [[ ! -f "$interface" ]] || ! grep -q 'type: "StateMacro"' "$interface"; then
        echo "$sdk"
        exit 0
    fi
done

echo "No usable macOS SDK found. Install Xcode, or an older Command Line Tools SDK." >&2
exit 1

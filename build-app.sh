#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h}
output_dir="$project_dir/dist"
app_dir="$output_dir/CodexStatus.app"
build_dir="$project_dir/.build/manual-release"
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swift_interface="$sdk_path/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
sdk_compiler_version=$(sed -n 's|// swift-compiler-version: ||p' "$swift_interface" | head -1)

cd "$project_dir"
mkdir -p "$build_dir/module-cache"

swiftc \
    -O \
    -parse-as-library \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatus/*.swift \
    -o "$build_dir/CodexStatus"

swiftc \
    -O \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatusHook/*.swift \
    -o "$build_dir/CodexStatusHook"

swiftc \
    -O \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatusThreadScanner/*.swift \
    -o "$build_dir/CodexStatusThreadScanner"

swiftc \
    -O \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatusWatcher/*.swift \
    -o "$build_dir/CodexStatusWatcher"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Helpers"
cp "$build_dir/CodexStatus" "$app_dir/Contents/MacOS/CodexStatus"
cp "$build_dir/CodexStatusHook" "$app_dir/Contents/Helpers/CodexStatusHook"
cp "$build_dir/CodexStatusThreadScanner" "$app_dir/Contents/Helpers/CodexStatusThreadScanner"
cp "$build_dir/CodexStatusWatcher" "$app_dir/Contents/Helpers/CodexStatusWatcher"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"

# The watcher is copied out of the app bundle by the launch agent. Explicitly
# signing each helper keeps macOS from rejecting that copied executable.
for helper in "$app_dir"/Contents/Helpers/*; do
    codesign --force --sign - "$helper"
done
codesign --force --sign - "$app_dir"

echo "$app_dir"

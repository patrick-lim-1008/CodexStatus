#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
test_build_dir="$project_dir/.build/smoke-tests"
app_dir="$project_dir/dist/CodexStatus.app"
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swift_interface="$sdk_path/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
sdk_compiler_version=$(sed -n 's|// swift-compiler-version: ||p' "$swift_interface" | head -1)

cd "$project_dir"
./build-app.sh >/dev/null

mkdir -p "$test_build_dir/module-cache"
swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$test_build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatus/AppPreferences.swift \
    Sources/CodexStatus/CodexIntegrationInstaller.swift \
    Tests/AppPreferencesSmoke.swift \
    -o "$test_build_dir/AppPreferencesSmoke"
"$test_build_dir/AppPreferencesSmoke"

codesign --verify --deep --strict "$app_dir"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_dir/Contents/Info.plist")
ui_element=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_dir/Contents/Info.plist")
[[ "$version" == "0.2.2" ]] || { print -u2 "Unexpected version: $version"; exit 1; }
[[ "$build" == "4" ]] || { print -u2 "Unexpected build: $build"; exit 1; }
[[ "$ui_element" == "true" ]] || { print -u2 "App must remain menu-bar only"; exit 1; }

for executable in \
    "$app_dir/Contents/MacOS/CodexStatus" \
    "$app_dir/Contents/Helpers/CodexStatusHook" \
    "$app_dir/Contents/Helpers/CodexStatusThreadScanner" \
    "$app_dir/Contents/Helpers/CodexStatusWatcher"
do
    file "$executable" | grep -q 'arm64' || { print -u2 "Not arm64: $executable"; exit 1; }
done

"$app_dir/Contents/Helpers/CodexStatusThreadScanner" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-scanner-output

"$app_dir/Contents/Helpers/CodexStatusThreadScanner" --parse-rollout \
    < "$project_dir/Tests/Fixtures/rollout-activity.jsonl" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-rollout-output

print "CodexStatus v$version ($build) smoke tests passed"

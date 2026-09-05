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
    Sources/CodexStatus/AppUpdateChecker.swift \
    Sources/CodexStatus/AppPreferences.swift \
    Sources/CodexStatus/CoreStateSupport.swift \
    Sources/CodexStatus/CodexIntegrationInstaller.swift \
    Sources/CodexStatus/CodexLifecycleInstaller.swift \
    Sources/CodexStatus/OptionalFeatureSupport.swift \
    Tests/AppPreferencesSmoke.swift \
    -o "$test_build_dir/AppPreferencesSmoke"
"$test_build_dir/AppPreferencesSmoke"

swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$test_build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatus/PluginSystem.swift \
    Tests/PluginSystemSmoke.swift \
    -o "$test_build_dir/PluginSystemSmoke"
"$test_build_dir/PluginSystemSmoke"

swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$test_build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatus/AppPreferences.swift \
    Sources/CodexStatus/PluginSystem.swift \
    Sources/CodexStatus/PromptLibraryPlugin.swift \
    Sources/CodexStatus/PromptLibrarySupport.swift \
    Tests/PromptLibrarySmoke.swift \
    -o "$test_build_dir/PromptLibrarySmoke"
"$test_build_dir/PromptLibrarySmoke"

swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$test_build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatus/SingleInstanceGuard.swift \
    Tests/SingleInstanceSmoke.swift \
    -o "$test_build_dir/SingleInstanceSmoke"
"$test_build_dir/SingleInstanceSmoke"

swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$test_build_dir/module-cache" \
    -interface-compiler-version "$sdk_compiler_version" \
    Sources/CodexStatus/MenuBarLayoutSupport.swift \
    Tests/MenuBarLayoutSmoke.swift \
    -o "$test_build_dir/MenuBarLayoutSmoke"
"$test_build_dir/MenuBarLayoutSmoke"

if [[ "${CODEX_STATUS_RUN_NETWORK_TESTS:-0}" == "1" ]]; then
    swiftc \
        -parse-as-library \
        -sdk "$sdk_path" \
        -target arm64-apple-macosx13.0 \
        -module-cache-path "$test_build_dir/module-cache" \
        -interface-compiler-version "$sdk_compiler_version" \
        Sources/CodexStatus/AppUpdateChecker.swift \
        Tests/AppUpdateCheckerLiveSmoke.swift \
        -o "$test_build_dir/AppUpdateCheckerLiveSmoke"
    "$test_build_dir/AppUpdateCheckerLiveSmoke"
fi

codesign --verify --deep --strict "$app_dir"

plugin_count=$(find "$app_dir/Contents/Resources/Plugins" -name manifest.json -maxdepth 2 | wc -l | tr -d ' ')
[[ "$plugin_count" == "2" ]] || { print -u2 "Expected 2 bundled plugin manifests, found $plugin_count"; exit 1; }

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_dir/Contents/Info.plist")
ui_element=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_dir/Contents/Info.plist")
[[ "$version" == "0.3.1" ]] || { print -u2 "Unexpected version: $version"; exit 1; }
[[ "$build" == "8" ]] || { print -u2 "Unexpected build: $build"; exit 1; }
[[ "$ui_element" == "true" ]] || { print -u2 "App must remain menu-bar only"; exit 1; }

for executable in \
    "$app_dir/Contents/MacOS/CodexStatus" \
    "$app_dir/Contents/Resources/Plugins/com.codexstatus.progress-sidecar.codexstatusplugin/Helpers/CodexStatusProgress" \
    "$app_dir/Contents/Helpers/CodexStatusHook" \
    "$app_dir/Contents/Helpers/CodexStatusThreadScanner" \
    "$app_dir/Contents/Helpers/CodexStatusWatcher"
do
    file "$executable" | grep -q 'arm64' || { print -u2 "Not arm64: $executable"; exit 1; }
done

CODEX_CLI_PATH="$project_dir/Tests/Fixtures/fake-codex-app-server.zsh" \
CODEX_STATUS_INCLUDE_USAGE=1 \
    "$app_dir/Contents/Helpers/CodexStatusThreadScanner" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-scanner-output

CODEX_CLI_PATH="/path/that/does/not/exist/codex" \
    "$app_dir/Contents/Helpers/CodexStatusThreadScanner" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-scanner-shape

CODEX_CLI_PATH="$project_dir/Tests/Fixtures/fake-codex-app-server.zsh" \
CODEX_STATUS_INCLUDE_USAGE=1 \
FAKE_RATE_LIMIT_PROFILE=weekly-only \
    "$app_dir/Contents/Helpers/CodexStatusThreadScanner" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-weekly-only-usage

"$app_dir/Contents/Helpers/CodexStatusThreadScanner" --parse-rollout \
    < "$project_dir/Tests/Fixtures/rollout-activity.jsonl" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-rollout-output

print -rn -- '{"threadID":"test-thread","prompt":"Give a concise progress update without changing anything."}' \
    | CODEX_CLI_PATH="$project_dir/Tests/Fixtures/fake-codex-app-server.zsh" \
        "$app_dir/Contents/Resources/Plugins/com.codexstatus.progress-sidecar.codexstatusplugin/Helpers/CodexStatusProgress" \
    | "$test_build_dir/AppPreferencesSmoke" --validate-progress-output

print "CodexStatus v$version ($build) smoke tests passed"

# CodexStatus

CodexStatus is an unofficial, lightweight native macOS menu bar companion for live OpenAI Codex task states. It uses a compact Codex-shaped status mark rather than a generic dot, rendered as an AppKit `NSStatusItem` with a non-template image so custom colors remain visible, with a SwiftUI popover.

This is an independent community project and is not affiliated with or endorsed by OpenAI.

## Requirements

- macOS 13 or later
- Apple Silicon Mac for the included app build script
- Codex desktop app installed and signed in
- Apple Command Line Tools (`xcode-select --install`)

## Run

Double-click `CodexStatus.app`, or build it locally:

```sh
chmod +x build-app.sh
./build-app.sh
open dist/CodexStatus.app
```

The included build script works with the standalone Apple Command Line Tools, so a full Xcode installation is not required. `Package.swift` is also included for opening or evolving the source as a Swift package.

The app has no Dock icon. Look for the colored Codex-shaped mark in the menu bar. Click the gear in its compact popover—or right-click the menu-bar mark and choose **Settings…**—to customize it.

## Settings and built-in extensions

Version 0.2 separates the quiet task indicator from optional capabilities:

- **Core:** local task detection, five status colors, priority/count display, exact conversation opening, idle folding, and persistent completed-task acknowledgement.
- **Usage Meter:** displays locally reported rate-limit windows. Enabled by default.
- **Enhanced Activity:** installs additive user-level Codex lifecycle hooks for more precise approval and failure signals. Disabled by default on a new installation.
- **macOS Notifications:** announces completion, approval/attention, and failure transitions. Each event has its own switch, sound, and test button, with optional quiet hours. Disabled by default.

Appearance settings control project labels, menu-bar counts, multi-state color cycling, and idle folding. General settings control completion acknowledgement and whether CodexStatus follows the Codex app lifecycle.

Existing v0.1 installations retain their enabled hooks, lifecycle behavior, and hover-to-read interaction when upgraded. Fresh installations use click-to-read and do not install hooks or a background watcher unless those options are enabled.

All v0.2 extensions are built into and signed with the app. CodexStatus does not load third-party executable code; a safely isolated external extension format is intentionally deferred.

New Codex activity appears automatically. The app reads the persisted turn lifecycle, so a task remains blue throughout model thinking and tool work instead of guessing from its last-update time. A completed task remains green until it is acknowledged using the selected click or hover behavior; that acknowledgement is persisted across app restarts.

Ordinary idle tasks are grouped into a collapsed row to keep the popover compact. Unread completed tasks remain visible until acknowledged, then join the idle group. The idle row can be expanded whenever older tasks are needed.

Existing and older tasks are loaded from Codex's supported App Server `thread/list` interface, so they appear without waiting for a new hook event. Lifecycle hooks add approval and failure signals. Click any task row to open that exact conversation in Codex.

When a task has a real working-directory project context, its row includes a compact folder suffix with the project name. Codex's generated projectless-chat directories are filtered out, and internal `g-p-*` identifiers are never displayed. Opening the row returns to that conversation in its original project context.

The usage indicator reads ChatGPT rate-limit windows from Codex's local App Server. When a 5-hour limit is present, it simultaneously shows a compact weekly ring and a 5-hour bar. Accounts without a 5-hour window automatically use the original single-ring view for the most constrained available window. Its expanded hover target shows only the windows actually returned, including quota reset times and the last data-refresh time. Usage refreshes once per minute and remains optional when the active account does not expose rate limits.

The compact 224-point header reads `Codex · activity · refresh` on the left. Clicking the Codex identity and summary brings the Codex app to the foreground; refresh remains an independent control. Its far-right usage group reads `reset date · ring`; hovering it opens a persistent in-menu detail card with the quota, full reset timestamp, and data-refresh time. Conversation titles form a flexible left-aligned region that takes all remaining row width. Project suffixes stay right-aligned and grow only up to 116 points. No generic project icon is shown because Codex's thread metadata does not expose each project's configured icon. Long project names keep both their beginning and ending through middle truncation and reveal the complete untruncated name on hover. Redundant row status labels and disclosure chevrons are omitted. It has no footer.

A completed task remains green until it is seen. It becomes a neutral `Completed · viewed` row, remains visible, and the acknowledgement is persisted. New installations mark it read when the task is clicked; upgraded users retain the original hover-to-read behavior, and either mode can be selected in Settings.

When **Follow Codex lifecycle** is enabled, CodexStatus installs a lightweight user LaunchAgent watcher. The watcher has no UI and only observes whether the Codex app bundle is running: it opens CodexStatus when Codex starts and terminates CodexStatus when Codex quits. Disabling the setting removes that watcher.

## Privacy

CodexStatus runs locally. It reads Codex task metadata and, when enabled, rate-limit information from the local Codex App Server. Enhanced Activity stores only small lifecycle snapshots and completion acknowledgements on your Mac. CodexStatus itself does not upload analytics or user data. The About & Privacy settings include controls to open its data folder and safely remove only the integrations installed by CodexStatus.

## Status priority

`Error > Needs Attention > Working > Done > Idle`

The menu bar number appears only when more than one task shares the highest-priority status.

A stopped task remains red for five minutes, then becomes a folded idle entry unless Codex reports new activity.

When two or more active statuses coexist, the menu-bar mark cycles through each active status color and its count every 1.3 seconds. Read completion rows are neutral and do not join the cycle.

## License

CodexStatus is available under the [MIT License](LICENSE).

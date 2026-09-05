# Changelog

## 0.3.0

- Add PluginKit v1 with versioned `.codexstatusplugin` manifests, capability and privacy declarations, and a native settings importer.
- Separate settings into built-in default, built-in optional, and plugin layers.
- Safely allow declarative resource packs while rejecting imported executables, symbolic links, incompatible packages, and attempts to replace bundled plugins.
- Move Progress Sidecar into a signed bundled native plugin package with manual or scheduled `/side`-style progress summaries.
- Keep Sidecar requests ephemeral and read-only so progress checks do not add turns to or steer the source task.
- Prevent stale App Server and Hook signals from overriding newer completed, aborted, or running task state.
- Stop stale active tasks from remaining blue after Codex becomes unavailable.
- Read both legacy and multi-limit App Server usage responses, including 5-hour and weekly windows.
- Keep model-specific rate-limit buckets separate so they cannot masquerade as the account's general 5-hour limit.
- Recover safely from corrupt completion history and cap its stored acknowledgement ledger.
- Return a structured disconnected result when the Codex executable or App Server is unavailable.
- Consolidate Enhanced Activity, notifications, lifecycle following, and update checks under built-in optional features.
- Add opt-in stable CodexStatus release checks against the public GitHub releases endpoint, with an update badge only when action is needed.
- Add System, Light, and Dark appearance choices as the built-in base for future theme packs.
- Report notification permission and lifecycle watcher readiness instead of displaying an optimistic enabled state.
- Add idempotent install/uninstall tests for lifecycle hooks and the background watcher, plus quiet-hours boundary tests.

## 0.2.2

- Show specific live task activity directly in each task row, including terminal use, file edits, web search, integrations, subtasks, image generation, and response writing.
- Derive activity from local Codex rollout events without exposing prompts, reasoning, commands, paths, or tool output.
- Keep the task list compact with no redundant activity disclosure layer.

## 0.2.1

- Split macOS notifications into independent Completed, Needs Attention, and Error rules.
- Add a separate enable switch, sound choice, and test button for each notification type.
- Add optional quiet hours while keeping test notifications immediately available.
- Preserve the original notification sound preference when upgrading from version 0.2.0.

## 0.2.0

- Add a native settings window with General, Appearance, Extensions, and About & Privacy sections.
- Add persistent preferences for lifecycle behavior, completion acknowledgement, project labels, menu-bar counts, status cycling, and idle folding.
- Add built-in Usage Meter, Enhanced Activity, and macOS Notifications extensions.
- Make Codex lifecycle hooks and the background watcher explicitly controllable and safely removable.
- Preserve existing installations while using privacy-first defaults for new users.

## 0.1.0

- Initial open-source release.

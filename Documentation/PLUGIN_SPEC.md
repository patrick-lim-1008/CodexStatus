# CodexStatus PluginKit v1

PluginKit v1 is reserved for independently packaged capabilities. Ordinary
built-in settings are not plugins. Native plugins ship inside the signed app;
imported packages never execute third-party code.

## Package layout

A plugin is a directory whose name ends in `.codexstatusplugin`:

```text
Example.codexstatusplugin/
  manifest.json
  Resources/
    prompts.json
```

`manifest.json` is required. Packages may contain no more than 256 files or
25 MB in total. Symbolic links and executable files are rejected. The manifest
itself is limited to 128 KB.

## Manifest

```json
{
  "schemaVersion": 1,
  "identifier": "com.example.prompt-pack",
  "name": "Example Prompt Pack",
  "version": "1.0.0",
  "minimumHostVersion": "0.2.2",
  "author": "Example Author",
  "summary": "Adds a small set of reusable prompts.",
  "symbolName": "text.bubble",
  "kind": "resourcePack",
  "capabilities": ["providePrompts"],
  "privacyDescription": "Adds local text presets and does not access task data."
}
```

- `schemaVersion` must be `1`.
- `identifier` uses reverse-domain form and uniquely identifies the plugin.
- `version` and `minimumHostVersion` contain one to four numeric components.
- `kind` is `native` or `resourcePack`.
- `entryPoint` is required only for bundled native plugins.
- `capabilities` must accurately describe every host feature the plugin needs.
- `privacyDescription` explains the effect in user-facing language.

## Trust model

Bundled `native` plugins are compiled and signed with CodexStatus. Imported
plugins must be `resourcePack`; an imported package declaring `native` is
rejected. Imported plugins are copied to:

```text
~/Library/Application Support/CodexStatus/Plugins/
```

They are disabled after installation until the user explicitly enables them.
An imported plugin cannot replace a bundled plugin identifier. Re-importing the
same identifier performs an atomic same-version or newer-version update.

## Prompt resource packs

A resource pack declaring `providePrompts` may include
`Resources/prompts.json`:

```json
{
  "schemaVersion": 1,
  "presets": [{
    "id": "review-only",
    "title": "Review Only",
    "prompt": "Review the current changes.",
    "constraints": "Do not modify files."
  }]
}
```

The file is limited to 512 KB and 100 presets. A prompt is limited to 6,000
characters and its constraints to 4,000 characters. Enabled packs are read
locally; choosing a preset copies the combined text and opens the selected task.
CodexStatus never injects an imported prompt into a task automatically.

## Bundled native plugins

- `com.codexstatus.progress-sidecar`
- `com.codexstatus.prompt-library`

Progress Sidecar owns its prompt, manual and scheduled refresh behavior,
temporary side-conversation helper, quota warning, and task-row presentation.
The core provides only current task snapshots and the popover display slot.

Prompt & Constraint Library is a bundled resource pack and host picker. It also
loads enabled imported prompt packs and keeps user-created presets locally.

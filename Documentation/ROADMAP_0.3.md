# Roadmap to 0.3

Version 0.3.0 establishes the common foundation. Work was ordered by feature
layer rather than by the order ideas were proposed.

## 1. Built in and default on

These make CodexStatus a reliable status companion on a fresh installation:

- [x] accurate task lifecycle and activity detection;
- [x] compact multi-state menu-bar indication and stable count layout;
- [x] exact task navigation and clear project identity;
- [x] idle folding and persistent completion acknowledgement;
- [x] local quota windows with account-aware fallback;
- [x] safe migrations, crash recovery, and useful unavailable states.

Released in version 0.3.0.

## 2. Built in and user enabled

These are useful to many people but may interrupt the user, install a local
integration, access the network, or change the visual experience:

- [x] Enhanced Activity lifecycle hooks;
- [x] completion, attention, and failure notifications with sounds and quiet hours;
- [x] following the Codex app lifecycle;
- [x] CodexStatus stable-release availability checks;
- [x] a System/Light/Dark theme engine, while third-party themes remain resource packs.

Codex release notes and update summaries are intentionally not part of this
layer. They require an external content source and remain planned plugins.

## 3. Plugins

These have a narrower audience, use model quota or external services, or make
sense as independently maintained content:

- Progress Sidecar;
- prompt and constraint libraries;
- Codex release summaries;
- reset-probability integrations;
- pet and theme resource packs.

## 0.3 release gate

- The first two layers have clear defaults and upgrade migrations.
- Plugin import, validation, enable/disable, update, and removal pass tests.
- Bundled plugins fail gracefully when Codex or an external dependency is not
  available.
- The app passes smoke, signing, launch, settings, and clean-up tests.
- Documentation distinguishes built-in features from plugins everywhere.

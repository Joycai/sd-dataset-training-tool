# Repository instructions

## Project and sources of truth

Dataset Toolkit is a Flutter desktop app for editing image datasets and captions,
with an optional Python AI backend in `AiApiServer/`. This file is the repository
entry point for Codex. Read `docs/ARCHITECTURE.md` for layer boundaries and
`docs/ENVIRONMENT_GUIDE.md` for platform setup when relevant to the task.
Existing `docs/plans/` documents provide design context; verify their status
against current code before treating old checklists as unfinished work.

## Toolchain and validation

Use the exact Flutter version pinned in `pubspec.yaml` (currently 3.47.6),
including its bundled Dart SDK. Do not upgrade dependencies to solve a local SDK
mismatch. Run commands from the repository root unless stated otherwise.

For app changes, use the CI checks in `.github/workflows/ci.yml`:

```text
flutter pub get
flutter gen-l10n
git status --porcelain lib/l10n
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
dart run tool/check_layers.dart
flutter test
```

Review localization status for generated changes and commit intended output.
Run focused tests during development, then the full gate for app changes before
handoff. For documentation or agent configuration changes, validate paths,
configuration syntax, and affected skill scripts; app tests are needed only if
those changes affect app behavior or build checks. Report unavailable checks.

## Code conventions

- Follow the existing layer-first layout and import table in
  `docs/ARCHITECTURE.md`; the checker and its tests must stay in sync with it.
- File I/O belongs in `lib/services/`. Dataset images and captions go through
  `DatasetStore`, exposed by `DatasetState.store`. UI image decoding via
  `Image.file`/`FileImage` is the documented exception.
- Use relative imports within `lib/`, and package imports for `lib/` in tests.
  Test paths mirror source paths; names end in `_test.dart`.
- Preserve Provider/ChangeNotifier ownership and the intentional mutual imports
  between `state/` and `agent/`. Generic architecture skills do not supersede
  the repository's established boundaries.
- Edit localization `.arb` sources and run `flutter gen-l10n`; do not hand-edit
  `app_localizations*.dart`. Preserve Chinese and English UI coverage.
- Follow `analysis_options.yaml`, including Future handling and cleanup of
  subscriptions and sinks. Use the formatter for Dart changes.

## Repository skills

Reusable workflows live in `.agents/skills/`. Load only skills relevant to the
request. `$bump-version` covers the three synchronized version fields;
`$update-models` covers backend model lists and metadata. The 22 upstream
Flutter/Dart skills retain their provenance in `skills-lock.json`; its
`skillPath` values describe paths in the upstream source, not this checkout.
Upstream `metadata.model` fields are provenance, not a request to switch the
Codex model. Use the current project SDK and actual available tools when a skill
mentions optional Dart/Flutter MCP tools; CLI checks and focused tests are the
fallback. Do not add packages merely because a generic skill uses them in an
example.

## Workflow and releases

Inspect Git status first and preserve unrelated local edits. Use `codex/`
branches for new work. Keep changes focused; never treat generated platform
file drift as permission to discard the user's changes. Do not modify or remove
legacy worktrees under `.claude/worktrees/` as part of routine development.

For substantial changes, keep a concrete plan in `docs/plans/` with scope,
validation and current status. Use `.github/PULL_REQUEST_TEMPLATE.md` for PRs.
Version changes belong in a release branch/PR and use `$bump-version`.
`.github/workflows/release.yml` creates tags and releases; do not manually create
version tags. Publishing a release requires a release request.

## Optional IDE integration

`.codex/config.toml` carries the migrated IntelliJ MCP connection. It depends on
the local IDE server being available; shell-based development does not require
it. Project configuration loads only in trusted projects. Keep the user's Codex
model, authentication and approval settings in their existing host profile;
Claude's local permission allow-list is not portable Codex policy.

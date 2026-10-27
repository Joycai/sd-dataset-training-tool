# Repository documentation refresh

Status: complete (2026-10-27). Documentation changes only.

## Scope

- Align the Chinese and English READMEs and wiki guides with the current
  caption formats, LLM protocols, per-model reasoning settings, optional tool
  groups, and image preprocessing/recovery workflow.
- Replace the placeholder clone command; document the exact Flutter pin,
  macOS deployment target, separate AI connections, and platform-specific
  backend installation paths.
- Align contributor validation and release instructions with the workflows.
- Use repository-readable Markdown links in the checked-in wiki guides.
- Preserve historical design plans and screenshots; no application, dependency,
  build configuration, or release changes.

## Sources checked

`pubspec.yaml`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`,
`macos/Runner.xcodeproj/project.pbxproj`, `lib/models/caption_type.dart`,
`lib/models/llm_models.dart`, `lib/models/llm_reasoning.dart`,
`lib/models/agent_tool_pack.dart`, `lib/services/llm/llm_client_factory.dart`,
`lib/views/dialogs/llm_profile_dialog.dart`,
`lib/agent/image_preprocess_tools.dart`, `lib/state/image_operation_state.dart`,
`lib/views/panels/image_operation_review.dart`, and
`lib/utils/platform_shortcuts.dart`.

## Validation

- Checked relative Markdown links and image references in all touched guides.
- Checked documented SDK, deployment target, protocols, defaults, and commands
  against source/configuration; reviewed both languages for equivalent coverage.
- `git diff --check` passed.
- Flutter tests and native builds were not run: no app behavior or build checks
  changed. External links and historical screenshots were not revalidated.

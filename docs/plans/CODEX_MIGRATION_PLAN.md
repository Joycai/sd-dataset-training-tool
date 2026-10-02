# Claude Code to Codex migration

Date: 2026-10-02 (Asia/Shanghai)
Branch: `codex/migrate-claude-workflow`
Baseline: `main` / `origin/main` at `724d9fb`.

## Goal and scope

Make Codex the repository's development agent while preserving the application's
behavior, existing design decisions, reusable workflows and contributor history.
This migrates development tooling, not the application's LLM providers or backend
models. The repository review covers architecture, tooling, CI, skills and Git
state; it is not a comprehensive application defect or security audit.

## Review findings

- `git fetch origin` succeeded. Local main and origin/main have zero commits of
  divergence, so no pull, merge or reset was necessary.
- No `CLAUDE.md` or `AGENTS.md` was found in the active checkout. Repository
  guidance already exists in `docs/ARCHITECTURE.md`, the environment guide,
  workflows and skills, so the migration creates an instruction entry point.
- The app uses Flutter/Provider with a layer checker and substantial unit/widget
  tests. `pubspec.yaml` pins Flutter 3.47.5, matching the installed SDK. Older
  documentation advertised 3.35+, which conflicts with the exact SDK pin.
- There are 24 tracked Claude skills: 22 upstream Flutter/Dart workflows and two
  project workflows (`bump-version`, `update-models`), plus one Python helper.
  Their frontmatter uses name/description and optional metadata; the upstream
  model annotations are provenance, not runtime model selection.
- `.mcp.json` defines only `idea`, a local HTTP MCP server at
  `http://127.0.0.1:64342/stream`. `.claude/settings.local.json` has local shell
  permissions and MCP enablement, with no hooks or custom agents to translate.
- A pre-existing change to `macos/Flutter/GeneratedPluginRegistrant.swift` and
  an old detached worktree in `.claude/worktrees/` must be preserved.
- The root skill lockfile records upstream source paths and hashes. Moving
  unchanged upstream files does not require rewriting those provenance values.

## Plan and execution

### 1. Synchronize safely — completed

Fetch origin, inspect divergence and local edits, and create a `codex/` branch.
The existing checkout was already current. Keep unrelated local changes intact.

### 2. Establish Codex instructions — completed

Create root `AGENTS.md` with toolchain, validation commands, architecture,
localization, Git and release conventions. Add `AiApiServer/AGENTS.md` for the
optional backend's static checks and model catalog constraints. Keep detailed
architecture in its existing document rather than duplicating the import table.

### 3. Migrate reusable workflows — completed

Move all 24 skills and their helper into `.agents/skills/`, preserving content and
relative link depth. Update the model checker invocation in its skill and script.
Preserve upstream skill metadata and `skills-lock.json`. Repository conventions
and the actual installed SDK take precedence over generic skill examples.
Optional Dart/Flutter MCP tools mentioned by upstream skills may be unavailable;
use shell tooling and focused tests where applicable.

### 4. Translate integration configuration — completed; local IDE server unavailable

Replace the tracked `.mcp.json` with `.codex/config.toml`, preserving the existing
`idea` server URL. Inherit the user's current Codex model, login and approval
settings; do not translate Claude's allow-list into broader approvals. Leave the
old local Claude settings on disk and ignore them, along with legacy worktrees.
Codex project config requires project trust and a fresh client/session reload.
MCP configuration discovery and live IDE connectivity are separate checks.

### 5. Update workflow references and onboarding — completed

Update current skill paths in release comments and retained design plans, and
change executor references to Codex. Update CI's development-config exclusions
to `.agents/**` and `.codex/**`, preserving the existing build gate behavior.
Correct the SDK requirement in the environment guide and both README badges.
Link the instruction entry point and this plan from both READMEs. Preserve
historical Gemini/Claude contributor credits.

### 6. Validate and hand off — completed

- Confirm all original skill files exist at their new locations, with only the
  intended path substitutions, and names are unique and match directories.
- Run the skill-creator validator on all 24 skills.
- Parse the Codex TOML and CI YAML; verify Codex discovers `idea`.
- Run the relocated metadata script and architecture checker.
- Run Flutter analysis and existing tests as repository health baselines.
- Review whitespace, remaining legacy references and final Git status.

## Validation record

- Fetch/divergence: passed, `0 0` versus origin/main.
- Flutter toolchain: 3.47.5 / Dart 3.13.4, matches the manifest.
- Codex TOML: parsed successfully.
- `codex mcp get idea --json`: recognizes an enabled Streamable HTTP server at
  the migrated URL.
- `python .agents/skills/update-models/scripts/check_metadata.py`: passed;
  55 models, 45 metadata entries, no consistency problems.
- `dart run tool/check_layers.dart`: passed, zero violations.
- All 24 skills passed the skill-creator `quick_validate.py` checker. All 25
  relocated skill files match the baseline except the intended path updates;
  skill names are unique and match folder names.
- CI YAML parsed successfully; push and PR exclusions match the new directories.
- `flutter analyze --no-pub`: passed, no issues.
- `flutter test --no-pub`: passed, 977 tests with 3 skipped.
- Dart formatting: 183 files checked, zero changes required.
- Localization generation: passed, no tracked or untracked localization drift.
- Live IDE MCP initialize request: connection refused on port 64342. The local
  server is unavailable in this session; configuration discovery passed, but
  live tool access remains unverified. Start the IntelliJ MCP server and restart
  the Codex client/session to verify it. No global configuration was modified.
- `git diff --check`: passed after migration.

## Handoff and acceptance

Codex has discovered all 24 migrated repository skills in this workspace. A
fresh Codex session in this repository should load root instructions and
expose the 24 repository skills. Start in `AiApiServer/` when checking the nested
backend instruction chain. Verify available MCP tools after restarting with the
local IntelliJ server running. No model downloads are required for migration.

The migration is accepted when skills/configuration validate, project checks are
reported accurately, and unrelated local work remains intact. IDE availability
is optional for shell-based development. The migration is being committed and
submitted as a pull request to `main`; it does not publish an application release.

## Rollback

Before any rollback, save unrelated local changes and inspect Git status. The
baseline commit retains the original `.claude/skills/` and `.mcp.json`. Restore
only the reviewed migration paths from that baseline and remove only the newly
created migration files after inspecting them. If the migration is later
committed, prefer reverting that specific commit. Do not reset the entire
checkout or remove legacy worktrees: they may contain independent work. Claude's
local settings and existing worktrees have been left in place.

## Sources

- [Codex repository instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex local skills discovery](https://learn.chatgpt.com/docs/build-skills)
- [Codex project MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

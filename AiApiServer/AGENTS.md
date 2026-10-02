# AiApiServer instructions

This optional Flask backend provides tagging, captioning, background removal and
translation. Read `README.md` here and `../docs/ENVIRONMENT_GUIDE.md` for setup.
Use an isolated environment for backend execution (Python 3.12 recommended).
CI performs static checks on Python 3.11; preserve that syntax compatibility.

- `models.py` is the source of truth for model catalogs and picker metadata.
  Load `$update-models` for additions, removals or metadata changes. Keep paired
  names/thresholds and removal/resolution lists aligned; prefer marking a model
  legacy when saved client configurations may still reference it.
- Preserve the existing HTTP contracts consumed by the Flutter app. Model
  weights and GPU dependencies are unnecessary for static validation.
- Validate backend changes from the repository root:

  ```text
  python -m compileall -q AiApiServer
  ruff check AiApiServer
  python .agents/skills/update-models/scripts/check_metadata.py
  ```

  Use the installed Ruff or the CI equivalent `pipx run ruff check AiApiServer`.
  `ruff.toml` defines the existing lint scope. For client-facing changes run the
  affected Flutter tests too. Report separately whether actual model loading or
  inference was tested; it needs the appropriate hardware and dependencies.

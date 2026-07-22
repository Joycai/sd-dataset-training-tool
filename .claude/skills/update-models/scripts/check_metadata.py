"""Static consistency check for AiApiServer/models.py.

Cross-checks MODEL_METADATA keys against every model name list, and checks
the index-aligned parallel lists for length drift. Parses the file as AST so
it runs without torch or any server dependency.

Usage: python .claude/skills/update-models/scripts/check_metadata.py
Exit code 0 = consistent, 1 = problems printed.
"""
import ast
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[4] / "AiApiServer" / "models.py"

tree = ast.parse(SRC.read_text(encoding="utf-8"))

consts = {}
for node in tree.body:
    if (
        isinstance(node, ast.Assign)
        and len(node.targets) == 1
        and isinstance(node.targets[0], ast.Name)
    ):
        try:
            consts[node.targets[0].id] = ast.literal_eval(node.value)
        except ValueError:
            pass

problems = []

# --- every model name across all three buckets -------------------------
interrogators = set()
interrogators.update(consts["BLIP2_CAPTIONING_NAMES"])
interrogators.update(consts["FLORENCE2_CAPTIONING_NAMES"])
interrogators.update(consts["FLORENCE2PG_CAPTIONING_NAMES"])
interrogators.update(consts["MOONDREAM2_CAPTIONING_NAMES"])
interrogators.update(consts["JOYCAPTION_CAPTIONING_NAMES"])
interrogators.update(n for n, _ in consts["QWEN25_CAPTIONING_NAMES"])
interrogators.update(n for n, _ in consts["KEYE_CAPTIONING_NAMES"])
interrogators.update(consts["WD_TAGGER_NAMES"])
# Instances whose name() is hardcoded rather than a repo path.
interrogators.update(["BLIP", "GIT-large-COCO", "DeepDanbooru"])

editors = set(consts["BG_REMOVAL"])
translators = set(consts["SEED_X"])
all_models = interrogators | editors | translators

meta = set(consts["MODEL_METADATA"].keys())

# Interrogators must all be annotated (they feed the app's picker badges);
# editors/translators are optional but must not be stale.
missing = sorted(interrogators - meta)
stale = sorted(meta - all_models)
if missing:
    problems.append(f"interrogators missing metadata: {missing}")
if stale:
    problems.append(f"stale metadata keys (no matching model): {stale}")

# --- field sanity -------------------------------------------------------
ALLOWED = {"recommended", "uncensored", "legacy", "vram_gb", "description", "advice"}
for name, entry in consts["MODEL_METADATA"].items():
    bad = set(entry) - ALLOWED
    if bad:
        problems.append(f"unknown fields in {name}: {sorted(bad)}")

# --- index-aligned parallel lists --------------------------------------
pairs = [
    ("WD_TAGGER_NAMES", "WD_TAGGER_THRESHOLDS"),
    ("BG_REMOVAL", "BG_REMOVAL_RESOLUTION"),
]
for a, b in pairs:
    if len(consts[a]) != len(consts[b]):
        problems.append(
            f"parallel list length mismatch: {a} has {len(consts[a])}, "
            f"{b} has {len(consts[b])}"
        )

print(f"models: {len(all_models)} "
      f"(interrogators {len(interrogators)}, editors {len(editors)}, "
      f"translators {len(translators)}); metadata entries: {len(meta)}")
if problems:
    for p in problems:
        print("PROBLEM:", p)
    sys.exit(1)
print("OK: metadata consistent")

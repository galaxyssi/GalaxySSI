#!/usr/bin/env sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
export GALAXYSSI_SOURCE_ROOT="$REPO_ROOT"

echo "GalaxySSI source: $REPO_ROOT"
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

gh auth status --hostname github.com || echo "Authenticate on Desktop with: gh auth login" >&2
python3 "$SCRIPT_DIR/evolution-preflight.py" --repo-root "$REPO_ROOT"

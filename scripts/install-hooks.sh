#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"

ln -sf "../../scripts/pre-commit.sh" "$HOOK_PATH"
chmod +x "$REPO_ROOT/scripts/pre-commit.sh" "$REPO_ROOT/scripts/lint.sh"

echo "✓ pre-commit hook kuruldu: $HOOK_PATH → scripts/pre-commit.sh"

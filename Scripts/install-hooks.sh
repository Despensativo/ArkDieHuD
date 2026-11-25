#!/usr/bin/env bash
# ==============================================================================
# install-hooks.sh — Ativa os Git hooks locais offline em Scripts/hooks
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

chmod +x "$REPO_ROOT/Scripts/"*.sh "$REPO_ROOT/Scripts/hooks/"*
git -C "$REPO_ROOT" config core.hooksPath Scripts/hooks

ACTIVE_PATH="$(git -C "$REPO_ROOT" config --get core.hooksPath)"
echo "✅ Git hooks offline configurados com sucesso: core.hooksPath=$ACTIVE_PATH"
ls -la "$REPO_ROOT/Scripts/hooks"

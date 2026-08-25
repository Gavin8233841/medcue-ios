#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_DIR="$(git -C "$ROOT_DIR" rev-parse --git-path hooks)"
HOOK_PATH="$HOOK_DIR/pre-commit"
MARKER="# medcue-pre-commit-managed"

usage() {
    cat <<'USAGE'
Usage: tools/install-hooks.sh [--check]

Install or verify the MedCue staged pre-commit hook.

The installer backs up an existing non-managed hook and never rewrites source
files. Use --check to verify without changing Git metadata.
USAGE
}

fail() {
    printf 'install-hooks: %s\n' "$*" >&2
    exit 2
}

check_only=0
if [[ $# -gt 0 ]]; then
    case "$1" in
        --check)
            check_only=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
fi

[[ -x "$ROOT_DIR/tools/run-pre-commit-checks.sh" ]] ||
    fail "checker is missing or not executable: $ROOT_DIR/tools/run-pre-commit-checks.sh"
mkdir -p "$HOOK_DIR"

if [[ "$check_only" == 1 ]]; then
    [[ -f "$HOOK_PATH" ]] || fail "pre-commit hook is not installed: $HOOK_PATH"
    [[ -x "$HOOK_PATH" ]] || fail "pre-commit hook is not executable: $HOOK_PATH"
    grep -Fq "$MARKER" "$HOOK_PATH" || fail "pre-commit hook is not managed by MedCue: $HOOK_PATH"
    printf 'pre-commit hook verified: %s\n' "$HOOK_PATH"
    exit 0
fi

if [[ -L "$HOOK_PATH" ]]; then
    fail "refusing to replace a symbolic-link hook: $HOOK_PATH"
fi

if [[ -f "$HOOK_PATH" ]] && grep -Fq "$MARKER" "$HOOK_PATH"; then
    chmod +x "$HOOK_PATH"
    printf 'pre-commit hook already installed: %s\n' "$HOOK_PATH"
    exit 0
fi

if [[ -e "$HOOK_PATH" ]]; then
    timestamp="$(date +%Y%m%d%H%M%S)"
    backup_path="$HOOK_PATH.backup.$timestamp"
    counter=0
    while [[ -e "$backup_path" ]]; do
        counter=$((counter + 1))
        backup_path="$HOOK_PATH.backup.$timestamp.$counter"
    done
    cp -p "$HOOK_PATH" "$backup_path"
    printf 'backed up existing hook: %s\n' "$backup_path"
fi

{
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "$MARKER"
    printf '%s\n' 'set -Eeuo pipefail'
    printf '%s\n' 'ROOT_DIR="$(git rev-parse --show-toplevel)"'
    printf '%s\n' 'exec "$ROOT_DIR/tools/run-pre-commit-checks.sh"'
} >"$HOOK_PATH"
chmod +x "$HOOK_PATH"

"$HOOK_PATH"
printf 'pre-commit hook installed: %s\n' "$HOOK_PATH"

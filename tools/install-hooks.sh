#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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

if ! HOOKS_PATH="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)"; then
    fail "Git hooks path is disabled or cannot be resolved for $ROOT_DIR"
fi
if ! REPO_GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-dir 2>/dev/null)" ||
    ! COMMON_GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    fail "cannot resolve Git worktree directories for $ROOT_DIR"
fi

case "$HOOKS_PATH" in
    ''|.|./|"$ROOT_DIR")
        fail "Git hooks path is disabled or resolves to the repository root: $HOOKS_PATH"
        ;;
    *$'\n'*|*$'\r'*)
        fail "Git hooks path contains a control character: $HOOKS_PATH"
        ;;
    /*) HOOK_DIR="$HOOKS_PATH" ;;
    *) HOOK_DIR="$ROOT_DIR/$HOOKS_PATH" ;;
esac
HOOK_PATH="$HOOK_DIR/pre-commit"

if [[ "$REPO_GIT_DIR" != "$COMMON_GIT_DIR" && ( "$HOOKS_PATH" == "$COMMON_GIT_DIR" || "$HOOKS_PATH" == "$COMMON_GIT_DIR"/* ) ]]; then
    fail "refusing a hooks path inside the shared Git directory for a linked worktree: $HOOKS_PATH; configure a worktree-specific core.hooksPath"
fi

render_managed_hook() {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "$MARKER"
    printf '%s\n' 'set -Eeuo pipefail'
    printf '%s\n' 'ROOT_DIR="$(git rev-parse --show-toplevel)"'
    printf '%s\n' 'exec "$ROOT_DIR/tools/run-pre-commit-checks.sh"'
}

managed_hook_matches() {
    [[ -f "$HOOK_PATH" && ! -L "$HOOK_PATH" && -x "$HOOK_PATH" ]] || return 1
    render_managed_hook | cmp -s - "$HOOK_PATH"
}

check_only=0
if [[ $# -gt 0 ]]; then
    [[ $# -eq 1 ]] || fail "expected at most one argument"
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

if [[ "$check_only" == 1 ]]; then
    [[ -f "$HOOK_PATH" ]] || fail "pre-commit hook is not installed: $HOOK_PATH"
    [[ -x "$HOOK_PATH" ]] || fail "pre-commit hook is not executable: $HOOK_PATH"
    managed_hook_matches || fail "pre-commit hook is not an exact managed MedCue hook: $HOOK_PATH"
    printf 'pre-commit hook verified: %s\n' "$HOOK_PATH"
    exit 0
fi

mkdir -p "$HOOK_DIR"

if [[ -L "$HOOK_PATH" ]]; then
    fail "refusing to replace a symbolic-link hook: $HOOK_PATH"
fi

if [[ -e "$HOOK_PATH" && ! -f "$HOOK_PATH" ]]; then
    fail "refusing to replace a non-regular hook: $HOOK_PATH"
fi

if managed_hook_matches; then
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

render_managed_hook >"$HOOK_PATH"
chmod +x "$HOOK_PATH"

(cd "$ROOT_DIR" && "$HOOK_PATH")
printf 'pre-commit hook installed: %s\n' "$HOOK_PATH"

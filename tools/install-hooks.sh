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

CONFIGURED_HOOKS_PATH=''
# Keep the NUL-delimited scope/origin/value fields separate, including empty
# values. A command failure must not be mistaken for an unset hooks path.
hooks_config_fields=()
while IFS= read -r -d '' field; do
    hooks_config_fields[${#hooks_config_fields[@]}]="$field"
done < <(
    config_status=0
    git -C "$ROOT_DIR" config --null --show-scope --show-origin --get core.hooksPath 2>/dev/null || config_status=$?
    printf '%s\0' "$config_status"
)
if [[ ${#hooks_config_fields[@]} -eq 4 && "${hooks_config_fields[3]}" == 0 ]]; then
    case "${hooks_config_fields[0]}" in
        local|worktree) ;;
        *) fail 'refusing core.hooksPath from global, system, command, or unknown scope; configure a repository-local or worktree-specific path explicitly' ;;
    esac
    CONFIGURED_HOOKS_PATH="${hooks_config_fields[2]}"
    case "$CONFIGURED_HOOKS_PATH" in
        *[[:cntrl:]]*)
            fail 'Git hooks path contains a control character'
            ;;
    esac
elif [[ ${#hooks_config_fields[@]} -ne 1 || "${hooks_config_fields[0]}" != 1 ]]; then
    fail 'cannot verify the effective Git hooks path configuration scope'
fi
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
    *[[:cntrl:]]*)
        fail 'Git hooks path contains a control character'
        ;;
    /*) HOOK_DIR="$HOOKS_PATH" ;;
    *) HOOK_DIR="$ROOT_DIR/$HOOKS_PATH" ;;
esac
HOOK_PATH="$HOOK_DIR/pre-commit"
temporary_hook=''
report_temporary_hook() {
    [[ -z "$temporary_hook" ]] || printf 'temporary hook retained for inspection: %q\n' "$temporary_hook" >&2
}
trap report_temporary_hook EXIT

reject_symlink_components() {
    local path="$1"
    local remainder component current physical_current resolved

    [[ "$path" == /* ]] || return 0
    remainder="${path#/}"
    current="/"
    physical_current="/"
    while [[ -n "$remainder" ]]; do
        case "$remainder" in
            */*)
                component="${remainder%%/*}"
                remainder="${remainder#*/}"
                ;;
            *)
                component="$remainder"
                remainder=''
                ;;
        esac
        [[ -n "$component" ]] || continue
        if [[ "$current" == "/" ]]; then
            current="/$component"
        else
            current="$current/$component"
        fi
        if [[ -L "$current" ]]; then
            if [[ "$physical_current" == "$ROOT_DIR" || "$physical_current" == "$ROOT_DIR"/* ]]; then
                fail "Git hooks path contains a symbolic-link component: $current"
            fi
            if ! resolved="$(cd "$current" 2>/dev/null && pwd -P)"; then
                fail "Git hooks path contains an unresolvable symbolic-link component: $current"
            fi
            if [[ "$ROOT_DIR" != "$resolved"/* && "$COMMON_GIT_DIR" != "$resolved"/* ]]; then
                fail "Git hooks path contains a symbolic-link component: $current"
            fi
            physical_current="$resolved"
        elif [[ -d "$current" ]]; then
            physical_current="$(cd "$current" && pwd -P)"
        else
            physical_current="$physical_current/$component"
        fi
    done
}

if [[ -n "$CONFIGURED_HOOKS_PATH" ]]; then
    case "$CONFIGURED_HOOKS_PATH" in
        /*) CONFIGURED_HOOKS_DIR="$CONFIGURED_HOOKS_PATH" ;;
        *) CONFIGURED_HOOKS_DIR="$ROOT_DIR/$CONFIGURED_HOOKS_PATH" ;;
    esac
    reject_symlink_components "$CONFIGURED_HOOKS_DIR"
fi
reject_symlink_components "$HOOK_DIR"

if [[ "$REPO_GIT_DIR" != "$COMMON_GIT_DIR" && ( "$HOOKS_PATH" == "$COMMON_GIT_DIR" || "$HOOKS_PATH" == "$COMMON_GIT_DIR"/* ) ]]; then
    fail "refusing a hooks path inside the shared Git directory for a linked worktree: $HOOKS_PATH; configure a worktree-specific core.hooksPath"
fi

render_managed_hook() {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "$MARKER"
    printf '%s\n' 'set -Eeuo pipefail'
    printf '%s\n' 'ROOT_DIR="$(git rev-parse --show-toplevel)"'
    printf '%s\n' 'cd "$ROOT_DIR"'
    printf '%s\n' "git show ':tools/run-pre-commit-checks.sh' | bash -s --"
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
reject_symlink_components "$HOOK_DIR"

if [[ -L "$HOOK_PATH" ]]; then
    fail "refusing to replace a symbolic-link hook: $HOOK_PATH"
fi

if [[ -e "$HOOK_PATH" && ! -f "$HOOK_PATH" ]]; then
    fail "refusing to replace a non-regular hook: $HOOK_PATH"
fi

if managed_hook_matches; then
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

if ! temporary_hook="$(mktemp "$HOOK_DIR/.pre-commit.XXXXXX")"; then
    fail "cannot create a temporary managed hook in: $HOOK_DIR"
fi
if ! render_managed_hook >"$temporary_hook"; then
    fail "cannot render the managed hook"
fi
if ! chmod +x "$temporary_hook"; then
    fail "cannot mark the managed hook executable"
fi
if ! mv -f "$temporary_hook" "$HOOK_PATH"; then
    fail "cannot atomically install the managed hook: $HOOK_PATH"
fi
temporary_hook=''

(cd "$ROOT_DIR" && "$HOOK_PATH")
printf 'pre-commit hook installed: %s\n' "$HOOK_PATH"

#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/tools/pre-commit-checks.json"

usage() {
    cat <<'USAGE'
Usage: tools/run-pre-commit-checks.sh

Checks the staged Git index without modifying working-tree files.
USAGE
}

fail() {
    printf 'pre-commit-checks: %s\n' "$*" >&2
    exit 2
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
fi

[[ -f "$CONFIG_FILE" ]] || fail "configuration file not found: $CONFIG_FILE"
command -v git >/dev/null 2>&1 || fail "git is required"

PYTHON_BIN="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_BIN" ]] || fail "Python 3 is required to read the checked-in allowlist configuration"

policy_file="$(mktemp -t medcue-precommit-policy.XXXXXX)"
patterns_file="$(mktemp -t medcue-precommit-patterns.XXXXXX)"
diff_file="$(mktemp -t medcue-precommit-diff.XXXXXX)"
added_file="$(mktemp -t medcue-precommit-added.XXXXXX)"
files_file="$(mktemp -t medcue-precommit-files.XXXXXX)"
trap 'rm -f "$policy_file" "$patterns_file" "$diff_file" "$added_file" "$files_file"' EXIT

"$PYTHON_BIN" - "$CONFIG_FILE" >"$policy_file" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
data = json.loads(config_path.read_text(encoding="utf-8"))
policy = data["policy"]
source_package_path = config_path.parent / "build-source-package.py"
source_package_text = source_package_path.read_text(encoding="utf-8")

patterns = {
    "posix-users-root": r"/(?:Users)/",
    "posix-home-root": r"/(?:home)/",
    "posix-private-root": r"/(?:private)/",
    "posix-volumes-root": r"/(?:Volumes)/",
    "windows-drive-root": r"[A-Za-z]:[\\/]",
}
for pattern_id in policy["absolutePathPatterns"]:
    try:
        pattern = patterns[pattern_id]
    except KeyError as exc:
        raise SystemExit(f"unknown absolute path pattern id: {pattern_id}") from exc
    print(f"absolute\t{pattern}")

allowlist = policy["sourcePackageAllowlist"]
for path in allowlist["rootFiles"]:
    if "\n" in path or "\t" in path:
        raise SystemExit("allowlist root file contains a control separator")
    if f'    "{path}",' not in source_package_text:
        raise SystemExit(f"allowlist root file is not present in build-source-package.py: {path}")
    print(f"root\t{path}")
for prefix in allowlist["prefixes"]:
    if "\n" in prefix or "\t" in prefix:
        raise SystemExit("allowlist prefix contains a control separator")
    if f'    "{prefix}",' not in source_package_text:
        raise SystemExit(f"allowlist prefix is not present in build-source-package.py: {prefix}")
    print(f"prefix\t{prefix}")
PY

awk -F '\t' 'index($0, "\t") && $1 == "absolute" { print substr($0, index($0, "\t") + 1) }' \
    "$policy_file" >"$patterns_file"

root_files=()
allowed_prefixes=()
while IFS=$'\t' read -r kind value; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
        root)
            root_files[${#root_files[@]}]="$value"
            ;;
        prefix)
            allowed_prefixes[${#allowed_prefixes[@]}]="$value"
            ;;
    esac
done <"$policy_file"

[[ ${#root_files[@]} -gt 0 ]] || fail "allowlist has no root files"
[[ ${#allowed_prefixes[@]} -gt 0 ]] || fail "allowlist has no prefixes"
[[ -s "$patterns_file" ]] || fail "absolute path pattern list is empty"

failures=0

printf '%s\n' 'MedCue staged pre-commit checks'

if git diff --cached --check; then
    printf '%s\n' '[PASS] staged whitespace check'
else
    printf '%s\n' '[FAIL] staged whitespace check' >&2
    printf '%s\n' 'Fix the reported lines before committing; no files were rewritten automatically.' >&2
    failures=$((failures + 1))
fi

git diff --cached --unified=0 --no-color -- >"$diff_file"
grep -E '^\+[^+]' "$diff_file" >"$added_file" || true
absolute_path_lines="$(grep -E -f "$patterns_file" "$added_file" || true)"
if [[ -n "$absolute_path_lines" ]]; then
    printf '%s\n' '[FAIL] absolute local path in added staged content' >&2
    printf '%s\n' "$absolute_path_lines" >&2
    printf '%s\n' 'Replace local machine paths with <PROJECT_ROOT> or another sanitized placeholder.' >&2
    failures=$((failures + 1))
else
    printf '%s\n' '[PASS] absolute local path check'
fi

git diff --cached --name-only --diff-filter=ACMR -z -- >"$files_file"

path_allowed() {
    local path="$1"
    local root_file
    local prefix

    for root_file in "${root_files[@]}"; do
        [[ "$path" == "$root_file" ]] && return 0
    done
    for prefix in "${allowed_prefixes[@]}"; do
        [[ "$path" == "$prefix"* ]] && return 0
    done
    return 1
}

while IFS= read -r -d '' path; do
    if path_allowed "$path"; then
        printf '[PASS] allowlisted staged path: %s\n' "$path"
    else
        printf '[FAIL] staged path is outside the source-package allowlist: %s\n' "$path" >&2
        failures=$((failures + 1))
    fi
done <"$files_file"

node_required=0
while IFS= read -r -d '' path; do
    case "$path" in
        *.js|*.mjs|*.cjs|*.json)
            node_required=1
            ;;
    esac
done <"$files_file"

if [[ "$node_required" == 1 ]]; then
    command -v node >/dev/null 2>&1 || {
        printf '%s\n' '[FAIL] Node.js is required for staged JavaScript/JSON syntax checks' >&2
        failures=$((failures + 1))
    }
fi

if [[ "$node_required" == 1 ]] && command -v node >/dev/null 2>&1; then
    while IFS= read -r -d '' path; do
        case "$path" in
            *.json)
                if git show ":$path" | node -e 'let input=""; process.stdin.setEncoding("utf8"); process.stdin.on("data", chunk => { input += chunk; }); process.stdin.on("end", () => JSON.parse(input));' 2>&1; then
                    printf '[PASS] JSON syntax: %s\n' "$path"
                else
                    printf '[FAIL] JSON syntax: %s\n' "$path" >&2
                    failures=$((failures + 1))
                fi
                ;;
            *.mjs)
                if git show ":$path" | node --check --input-type=module - 2>&1; then
                    printf '[PASS] JavaScript syntax: %s\n' "$path"
                else
                    printf '[FAIL] JavaScript syntax: %s\n' "$path" >&2
                    failures=$((failures + 1))
                fi
                ;;
            *.js|*.cjs)
                if git show ":$path" | node --check - 2>&1; then
                    printf '[PASS] JavaScript syntax: %s\n' "$path"
                else
                    printf '[FAIL] JavaScript syntax: %s\n' "$path" >&2
                    failures=$((failures + 1))
                fi
                ;;
        esac
    done <"$files_file"
fi

if [[ "$failures" -gt 0 ]]; then
    printf 'pre-commit-checks: %d check group(s) failed; commit blocked.\n' "$failures" >&2
    exit 1
fi

printf '%s\n' '[PASS] all staged pre-commit checks'

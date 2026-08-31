#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

CONFIG_RELATIVE="tools/pre-commit-checks.json"
SOURCE_PACKAGE_RELATIVE="tools/build-source-package.py"

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
    [[ $# -eq 1 ]] || fail "expected at most one argument"
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

command -v git >/dev/null 2>&1 || fail "git is required"
command -v awk >/dev/null 2>&1 || fail "awk is required"
command -v cmp >/dev/null 2>&1 || fail "cmp is required"

if ! ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    fail "cannot resolve the repository root"
fi
ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
cd "$ROOT_DIR"

PYTHON_BIN="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_BIN" ]] || fail "Python 3 is required to read the checked-in allowlist configuration"
if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
    fail "Python 3.8 or newer is required to read the checked-in allowlist configuration"
fi

policy_file=''
source_policy_file=''
records_file=''
patterns_file=''
diff_file=''
added_file=''
files_file=''
unmerged_file=''
cleanup() {
    [[ -z "$policy_file" ]] || rm -f "$policy_file"
    [[ -z "$source_policy_file" ]] || rm -f "$source_policy_file"
    [[ -z "$records_file" ]] || rm -f "$records_file"
    [[ -z "$patterns_file" ]] || rm -f "$patterns_file"
    [[ -z "$diff_file" ]] || rm -f "$diff_file"
    [[ -z "$added_file" ]] || rm -f "$added_file"
    [[ -z "$files_file" ]] || rm -f "$files_file"
    [[ -z "$unmerged_file" ]] || rm -f "$unmerged_file"
}
trap cleanup EXIT

policy_file="$(mktemp -t medcue-precommit-policy.XXXXXX)"
source_policy_file="$(mktemp -t medcue-precommit-source-policy.XXXXXX)"
records_file="$(mktemp -t medcue-precommit-records.XXXXXX)"
patterns_file="$(mktemp -t medcue-precommit-patterns.XXXXXX)"
diff_file="$(mktemp -t medcue-precommit-diff.XXXXXX)"
added_file="$(mktemp -t medcue-precommit-added.XXXXXX)"
files_file="$(mktemp -t medcue-precommit-files.XXXXXX)"
unmerged_file="$(mktemp -t medcue-precommit-unmerged.XXXXXX)"

if ! git ls-files --unmerged -z -- >"$unmerged_file"; then
    fail "cannot inspect the staged index for unmerged entries"
fi
if [[ -s "$unmerged_file" ]]; then
    fail "staged index contains unmerged entries; resolve conflicts before running staged checks"
fi

git show ":$CONFIG_RELATIVE" >"$policy_file" ||
    fail "staged configuration is missing: $CONFIG_RELATIVE"
git show ":$SOURCE_PACKAGE_RELATIVE" >"$source_policy_file" ||
    fail "staged source-package builder is missing: $SOURCE_PACKAGE_RELATIVE"

"$PYTHON_BIN" - "$policy_file" "$source_policy_file" >"$records_file" <<'PY'
import ast
import json
import re
import sys

policy_path, source_package_path = sys.argv[1:3]
try:
    with open(policy_path, encoding="utf-8") as handle:
        data = json.load(handle)
    with open(source_package_path, encoding="utf-8") as handle:
        source_package_text = handle.read()
except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
    raise SystemExit(f"cannot read staged policy sources: {exc}")

if not isinstance(data, dict) or data.get("schemaVersion") != 1:
    raise SystemExit("unsupported or missing pre-commit policy schemaVersion")
policy = data.get("policy")
if not isinstance(policy, dict):
    raise SystemExit("pre-commit policy must contain an object-valued policy")

patterns = {
    "posix-users-root": r"/(?:Users)/",
    "posix-home-root": r"/(?:home)/",
    "posix-private-root": r"/(?:private)/",
    "posix-volumes-root": r"/(?:Volumes)/",
    "windows-drive-root": r"[A-Za-z]:[\\/]",
}
pattern_ids = policy.get("absolutePathPatterns")
if not isinstance(pattern_ids, list) or not pattern_ids or any(not isinstance(item, str) for item in pattern_ids):
    raise SystemExit("absolutePathPatterns must be a non-empty list")
if len(pattern_ids) != len(dict.fromkeys(pattern_ids)):
    raise SystemExit("absolutePathPatterns contains duplicates")
for pattern_id in pattern_ids:
    try:
        pattern = patterns[pattern_id]
    except KeyError as exc:
        raise SystemExit(f"unknown absolute path pattern id: {pattern_id}") from exc
    print(f"absolute\t{pattern}")

syntax_parsers = {
    ".js": "javascript",
    ".mjs": "module",
    ".cjs": "javascript",
    ".json": "json",
}
syntax_extensions = policy.get("syntaxExtensions")
if (
    not isinstance(syntax_extensions, list)
    or not syntax_extensions
    or any(not isinstance(item, str) for item in syntax_extensions)
    or len(syntax_extensions) != len(dict.fromkeys(syntax_extensions))
):
    raise SystemExit("syntaxExtensions must be a non-empty list without duplicates")
for extension in syntax_extensions:
    if not isinstance(extension, str) or not re.fullmatch(r"\.[A-Za-z0-9]+", extension):
        raise SystemExit(f"invalid syntax extension: {extension!r}")
    if extension not in syntax_parsers:
        raise SystemExit(f"unsupported syntax extension: {extension}")
    print(f"syntax\t{extension}")

def assignment_value(module, name):
    matches = []
    for node in module.body:
        targets = []
        if isinstance(node, ast.Assign):
            targets = node.targets
            value = node.value
        elif isinstance(node, ast.AnnAssign):
            targets = [node.target]
            value = node.value
        else:
            continue
        if any(isinstance(target, ast.Name) and target.id == name for target in targets):
            matches.append(value)
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one literal {name} assignment in build-source-package.py")
    try:
        return ast.literal_eval(matches[0])
    except (TypeError, ValueError, SyntaxError) as exc:
        raise SystemExit(f"{name} must be a literal collection in build-source-package.py: {exc}")

try:
    source_module = ast.parse(source_package_text, filename=source_package_path)
except (SyntaxError, ValueError) as exc:
    raise SystemExit(f"staged source-package builder is not valid Python: {exc}")
builder_roots = assignment_value(source_module, "ROOT_FILES")
builder_prefixes = assignment_value(source_module, "ALLOWED_PREFIXES")
allowlist = policy.get("sourcePackageAllowlist")
if not isinstance(allowlist, dict):
    raise SystemExit("sourcePackageAllowlist must be an object")

def collection(name, value, accepted_types):
    if not isinstance(value, accepted_types):
        raise SystemExit(f"{name} must be a collection of strings without duplicates")
    items = list(value)
    def has_control_character(item):
        return any(ord(character) < 0x20 or ord(character) == 0x7F for character in item)
    if any(not isinstance(item, str) or has_control_character(item) for item in items):
        raise SystemExit(f"{name} contains a non-string or control character")
    if len(items) != len(dict.fromkeys(items)):
        raise SystemExit(f"{name} must not contain duplicates")
    return items

config_roots = collection("sourcePackageAllowlist.rootFiles", allowlist.get("rootFiles"), (list,))
config_prefixes = collection("sourcePackageAllowlist.prefixes", allowlist.get("prefixes"), (list,))
builder_roots = collection("ROOT_FILES", builder_roots, (set, list, tuple))
builder_prefixes = collection("ALLOWED_PREFIXES", builder_prefixes, (set, list, tuple))

def validate_relative_paths(name, values, require_trailing_slash):
    for item in values:
        if not item or item.startswith("/") or "\\" in item or ":" in item:
            raise SystemExit(f"{name} contains an empty or absolute path: {item!r}")
        components = item[:-1].split("/") if require_trailing_slash and item.endswith("/") else item.split("/")
        if require_trailing_slash:
            if not item.endswith("/") or not components:
                raise SystemExit(f"{name} entries must end with '/': {item!r}")
        if any(component in {"", ".", ".."} for component in components):
            raise SystemExit(f"{name} contains an unsafe relative path: {item!r}")

validate_relative_paths("rootFiles", config_roots, False)
validate_relative_paths("prefixes", config_prefixes, True)
validate_relative_paths("ROOT_FILES", builder_roots, False)
validate_relative_paths("ALLOWED_PREFIXES", builder_prefixes, True)
if set(config_roots) != set(builder_roots):
    raise SystemExit(
        "source-package root-file policy drift: "
        f"config-only={sorted(set(config_roots) - set(builder_roots))}, "
        f"builder-only={sorted(set(builder_roots) - set(config_roots))}"
    )
if set(config_prefixes) != set(builder_prefixes):
    raise SystemExit(
        "source-package prefix policy drift: "
        f"config-only={sorted(set(config_prefixes) - set(builder_prefixes))}, "
        f"builder-only={sorted(set(builder_prefixes) - set(config_prefixes))}"
    )
for path in config_roots:
    print(f"root\t{path}")
for prefix in config_prefixes:
    print(f"prefix\t{prefix}")
PY

mv "$records_file" "$policy_file"

awk -F '\t' 'index($0, "\t") && $1 == "absolute" { print substr($0, index($0, "\t") + 1) }' \
    "$policy_file" >"$patterns_file"

root_files=()
allowed_prefixes=()
syntax_extensions=()
while IFS=$'\t' read -r kind value; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
        root)
            root_files[${#root_files[@]}]="$value"
            ;;
        prefix)
            allowed_prefixes[${#allowed_prefixes[@]}]="$value"
            ;;
        syntax)
            syntax_extensions[${#syntax_extensions[@]}]="$value"
            ;;
    esac
done <"$policy_file"

[[ ${#root_files[@]} -gt 0 ]] || fail "allowlist has no root files"
[[ ${#allowed_prefixes[@]} -gt 0 ]] || fail "allowlist has no prefixes"
[[ -s "$patterns_file" ]] || fail "absolute path pattern list is empty"

syntax_enabled_for_path() {
    local path="$1"
    local extension
    case "$path" in
        *.mjs) extension='.mjs' ;;
        *.cjs) extension='.cjs' ;;
        *.json) extension='.json' ;;
        *.js) extension='.js' ;;
        *) return 1 ;;
    esac
    local configured_extension
    for configured_extension in "${syntax_extensions[@]}"; do
        [[ "$configured_extension" == "$extension" ]] && return 0
    done
    return 1
}

failures=0

printf '%s\n' 'MedCue staged pre-commit checks'

if git diff --cached --check --text --no-ext-diff --no-textconv; then
    printf '%s\n' '[PASS] staged whitespace check'
else
    printf '%s\n' '[FAIL] staged whitespace check' >&2
    printf '%s\n' 'Fix the reported lines before committing; no files were rewritten automatically.' >&2
    failures=$((failures + 1))
fi

if ! git diff --cached --unified=0 --no-color --text --no-ext-diff --no-textconv -- >"$diff_file"; then
    fail "staged diff scan failed"
fi
if ! "$PYTHON_BIN" - "$diff_file" "$added_file" <<'PY'
import sys

diff_path, added_path = sys.argv[1:3]
try:
    saw_diff = False
    in_hunk = False
    with open(diff_path, "rb") as source, open(added_path, "wb") as added:
        for line in source:
            if line.startswith(b"diff --git "):
                saw_diff = True
                in_hunk = False
                continue
            if line.startswith(b"@@ "):
                if not saw_diff:
                    raise ValueError("hunk appears before a diff header")
                in_hunk = True
                continue
            if in_hunk and line.startswith(b"+"):
                added.write(line[1:])
except (OSError, ValueError) as exc:
    print(f"staged diff scan failed: {exc}", file=sys.stderr)
    raise SystemExit(2)
PY
then
    fail "staged diff scan failed"
fi
if "$PYTHON_BIN" - "$patterns_file" "$added_file" <<'PY'
import re
import sys

patterns_path, added_path = sys.argv[1:3]
try:
    with open(patterns_path, "rb") as handle:
        patterns = [
            re.compile(line.rstrip(b"\n"))
            for line in handle
            if line.rstrip(b"\n")
        ]
    matched = False
    with open(added_path, "rb") as handle:
        for line in handle:
            if not any(pattern.search(line) for pattern in patterns):
                continue
            if not matched:
                sys.stderr.buffer.write(
                    b"[FAIL] absolute local path in added staged content\n"
                )
                matched = True
            sys.stderr.buffer.write(line)
            if not line.endswith(b"\n"):
                sys.stderr.buffer.write(b"\n")
    if matched:
        sys.stderr.write(
            "Replace local machine paths with <PROJECT_ROOT> or another "
            "sanitized placeholder.\n"
        )
        raise SystemExit(1)
except (OSError, re.error) as exc:
    print(f"absolute path scan failed: {exc}", file=sys.stderr)
    raise SystemExit(2)
PY
then
    printf '%s\n' '[PASS] absolute local path check'
else
    scan_status=$?
    if [[ "$scan_status" == 1 ]]; then
        failures=$((failures + 1))
    else
        fail "absolute path scan failed (status $scan_status)"
    fi
fi

git diff --cached --name-only --diff-filter=ACMRT -z -- >"$files_file"

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
    if syntax_enabled_for_path "$path"; then
        node_required=1
    fi
done <"$files_file"

if [[ "$node_required" == 1 ]]; then
    command -v node >/dev/null 2>&1 || {
        printf '%s\n' '[FAIL] Node.js is required for staged JavaScript/JSON syntax checks' >&2
        failures=$((failures + 1))
    }
fi

if [[ "$node_required" == 1 ]] && command -v node >/dev/null 2>&1; then
    while IFS= read -r -d '' path; do
        syntax_enabled_for_path "$path" || continue
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

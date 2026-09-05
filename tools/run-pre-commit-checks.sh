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

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/medcue-precommit.XXXXXX")"
report_temporary_files() {
    LC_ALL=C printf 'pre-commit diagnostic files retained for inspection: %q\n' "$temporary_root"
}
trap report_temporary_files EXIT
policy_file="$temporary_root/policy"
source_policy_file="$temporary_root/source-policy"
records_file="$temporary_root/records"
patterns_file="$temporary_root/patterns"
files_file="$temporary_root/paths"
unmerged_file="$temporary_root/unmerged"

if ! git ls-files --unmerged -z -- >"$unmerged_file" 2>/dev/null; then
    fail "cannot inspect the staged index for unmerged entries"
fi
if [[ -s "$unmerged_file" ]]; then
    fail "staged index contains unmerged entries; resolve conflicts before running staged checks"
fi

git show ":$CONFIG_RELATIVE" >"$policy_file" 2>/dev/null ||
    fail "staged configuration is missing: $CONFIG_RELATIVE"
git show ":$SOURCE_PACKAGE_RELATIVE" >"$source_policy_file" 2>/dev/null ||
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
except (OSError, UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("cannot read staged policy sources; check their encoding and JSON syntax")

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
        raise SystemExit("unknown absolute path pattern id") from exc
    print(f"absolute\t{pattern_id}\t{pattern}")

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
        raise SystemExit("invalid syntax extension")
    if extension not in syntax_parsers:
        raise SystemExit("unsupported syntax extension")
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
    except (TypeError, ValueError, SyntaxError):
        raise SystemExit(f"{name} must be a literal collection in build-source-package.py")

try:
    source_module = ast.parse(source_package_text, filename=source_package_path)
except (SyntaxError, ValueError):
    raise SystemExit("staged source-package builder is not valid Python")
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
            raise SystemExit(f"{name} contains an empty or absolute path")
        components = item[:-1].split("/") if require_trailing_slash and item.endswith("/") else item.split("/")
        if require_trailing_slash:
            if not item.endswith("/") or not components:
                raise SystemExit(f"{name} entries must end with '/'")
        if any(component in {"", ".", ".."} for component in components):
            raise SystemExit(f"{name} contains an unsafe relative path")

validate_relative_paths("rootFiles", config_roots, False)
validate_relative_paths("prefixes", config_prefixes, True)
validate_relative_paths("ROOT_FILES", builder_roots, False)
validate_relative_paths("ALLOWED_PREFIXES", builder_prefixes, True)
if set(config_roots) != set(builder_roots):
    raise SystemExit("source-package root-file policy drift; align the two staged policies")
if set(config_prefixes) != set(builder_prefixes):
    raise SystemExit("source-package prefix policy drift; align the two staged policies")
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

whitespace_failed=0
if git diff --cached --check --text --no-ext-diff --no-textconv >/dev/null 2>&1; then
    printf '%s\n' '[PASS] staged whitespace check'
else
    printf '%s\n' '[FAIL] staged whitespace check' >&2
    printf '%s\n' 'Rule staged-whitespace: fix whitespace errors in the index; source context is not printed.' >&2
    whitespace_failed=1
    failures=$((failures + 1))
fi

# Only post-image paths need allowlist and content checks. Treat renames as a
# deletion and an addition so Git's rename threshold cannot change coverage.
if ! git diff --cached --name-only --diff-filter=ACMRT --no-renames -z -- >"$files_file" 2>/dev/null; then
    fail "cannot enumerate staged paths"
fi
if "$PYTHON_BIN" - "$patterns_file" "$files_file" "$whitespace_failed" <<'PY'
import json
import os
import re
import subprocess
import sys

patterns_path, files_path = sys.argv[1:3]
whitespace_failed = sys.argv[3] == "1"
try:
    with open(patterns_path, "rb") as handle:
        patterns = []
        for record in handle:
            rule_id, pattern = record.rstrip(b"\n").split(b"\t", 1)
            patterns.append((rule_id.decode("ascii"), re.compile(pattern)))
    with open(files_path, "rb") as handle:
        paths = [path for path in handle.read().split(b"\0") if path]
    hunk_header = re.compile(rb"^@@ -[0-9]+(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@")
    matched = False
    for path in paths:
        # Read one literal path at a time, keeping its bytes separate from the
        # patch headers. Neither unusual names nor staged text reach diagnostics.
        result = subprocess.run(
            ["git", "--literal-pathspecs", "diff", "--cached", "--unified=0",
             "--no-color", "--text", "--no-ext-diff", "--no-textconv",
             "--no-renames", "--", os.fsdecode(path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if result.returncode:
            raise ValueError("diff failed")
        safe_path = json.dumps(os.fsdecode(path), ensure_ascii=True)
        if whitespace_failed:
            whitespace = subprocess.run(
                ["git", "--literal-pathspecs", "diff", "--cached", "--check",
                 "--text", "--no-ext-diff", "--no-textconv", "--", os.fsdecode(path)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            if whitespace.returncode:
                print(f"[FAIL] path={safe_path} rule=staged-whitespace", file=sys.stderr)
        new_line = None
        for line in result.stdout.split(b"\n"):
            if line.startswith(b"diff --git "):
                new_line = None
                continue
            if line.startswith(b"@@ "):
                header = hunk_header.match(line)
                if header is None:
                    raise ValueError("invalid hunk header")
                new_line = int(header.group(1))
                continue
            if new_line is None:
                continue
            if line.startswith(b"+"):
                for rule_id, pattern in patterns:
                    if pattern.search(line[1:]):
                        matched = True
                        print(
                            "[FAIL] absolute local path in added staged content: "
                            f"path={safe_path} line={new_line} rule={rule_id}",
                            file=sys.stderr,
                        )
            if line.startswith((b"+", b" ")):
                new_line += 1
    if matched:
        sys.stderr.write(
            "Replace local machine paths with <PROJECT_ROOT> or another "
            "sanitized placeholder.\n"
        )
        raise SystemExit(1)
except (OSError, ValueError, re.error):
    print("absolute path scan failed; staged source context is not printed", file=sys.stderr)
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

quote_path() {
    # C-locale shell escaping covers control bytes, invalid UTF-8 and bidi text.
    LC_ALL=C printf '%q' "$1"
}

while IFS= read -r -d '' path; do
    display_path="$(quote_path "$path")"
    if path_allowed "$path"; then
        printf '[PASS] allowlisted staged path: %s\n' "$display_path"
    else
        printf '[FAIL] staged path is outside the source-package allowlist: %s\n' "$display_path" >&2
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
        display_path="$(quote_path "$path")"
        case "$path" in
            *.json)
                if git show ":$path" 2>/dev/null | node -e 'let input=""; process.stdin.setEncoding("utf8"); process.stdin.on("data", chunk => { input += chunk; }); process.stdin.on("end", () => JSON.parse(input));' >/dev/null 2>&1; then
                    printf '[PASS] JSON syntax: %s\n' "$display_path"
                else
                    printf '[FAIL] JSON syntax: %s (rule json-syntax; source context suppressed)\n' "$display_path" >&2
                    failures=$((failures + 1))
                fi
                ;;
            *.mjs)
                if git show ":$path" 2>/dev/null | node --check --input-type=module - >/dev/null 2>&1; then
                    printf '[PASS] JavaScript syntax: %s\n' "$display_path"
                else
                    printf '[FAIL] JavaScript syntax: %s (rule javascript-syntax; source context suppressed)\n' "$display_path" >&2
                    failures=$((failures + 1))
                fi
                ;;
            *.js|*.cjs)
                if git show ":$path" 2>/dev/null | node --check - >/dev/null 2>&1; then
                    printf '[PASS] JavaScript syntax: %s\n' "$display_path"
                else
                    printf '[FAIL] JavaScript syntax: %s (rule javascript-syntax; source context suppressed)\n' "$display_path" >&2
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

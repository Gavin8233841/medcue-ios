#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/tools/pre-commit-checks.json"
CHECKER="$ROOT_DIR/tools/run-pre-commit-checks.sh"
INSTALLER="$ROOT_DIR/tools/install-hooks.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/native-verification.yml"

fail() {
    printf 'test-pre-commit-system: %s\n' "$*" >&2
    exit 1
}

for path in "$CONFIG_FILE" "$CHECKER" "$INSTALLER" "$WORKFLOW"; do
    [[ -f "$path" ]] || fail "required file missing: $path"
done
[[ -f "$ROOT_DIR/tools/build-source-package.py" ]] || fail "source-package allowlist source is missing"

[[ -x "$CHECKER" ]] || fail "checker is not executable: $CHECKER"
[[ -x "$INSTALLER" ]] || fail "installer is not executable: $INSTALLER"

command -v python3 >/dev/null 2>&1 || fail "python3 is required for configuration validation"
python3 -m json.tool "$CONFIG_FILE" >/dev/null

bash -n "$CHECKER"
bash -n "$INSTALLER"

grep -Fq 'git diff --check' "$WORKFLOW" || fail "CI whitespace check is not present"
grep -Fq 'node --check' "$WORKFLOW" || fail "CI JavaScript syntax check is not present"
grep -Fq 'tools/verify-native.sh' "$WORKFLOW" || fail "native verification entrypoint is not present"

if command -v node >/dev/null 2>&1; then
    node --check "$ROOT_DIR/tools/openai-image-api-server.mjs"
    node --check "$ROOT_DIR/cloudfunctions/medcue-ai-broker/index.js"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
        "$ROOT_DIR/cloudfunctions/medcue-ai-broker/package.json"
else
    printf '%s\n' 'warning: node is unavailable; JavaScript/JSON smoke checks skipped'
fi

git -C "$ROOT_DIR" diff --cached --check --text --no-ext-diff --no-textconv
"$CHECKER"

run_fixture_boundary_tests() {
    local temp_root fixture fixture_physical fixture_index output hook_path backup_count
    local absolute_hooks absolute_hook_path linked_fixture shared_custom_hooks textconv_script textconv_marker fake_local_path
    local symlink_hooks symlink_target absolute_symlink_hooks absolute_symlink_target fake_bin
    local external_hooks_parent external_hooks_link conflict_sha hardlink_hooks hardlink_target
    temp_root="${TMPDIR:-/tmp}"
    fixture="$(mktemp -d "$temp_root/medcue-precommit-fixture.XXXXXX")"
    fixture_physical="$(cd "$fixture" && pwd -P)"
    fixture_index="$fixture/isolated-index"

    mkdir -p "$fixture/tools"
    cp -p "$CONFIG_FILE" "$fixture/tools/pre-commit-checks.json"
    cp -p "$ROOT_DIR/tools/build-source-package.py" "$fixture/tools/build-source-package.py"
    cp -p "$CHECKER" "$fixture/tools/run-pre-commit-checks.sh"
    cp -p "$INSTALLER" "$fixture/tools/install-hooks.sh"
    printf '%s\n' 'safe baseline content' >"$fixture/tools/fixture-textconv.txt"
    printf '%s\n' 'safe binary baseline content' >"$fixture/tools/fixture-binary.txt"
    printf '%s\n' 'fixture-binary.txt binary' >"$fixture/tools/.gitattributes"

    git -C "$fixture" init -q
    git -C "$fixture" config user.name 'MedCue fixture'
    git -C "$fixture" config user.email 'fixture@example.invalid'
    git -C "$fixture" add -- \
        tools/pre-commit-checks.json \
        tools/build-source-package.py \
        tools/run-pre-commit-checks.sh \
        tools/install-hooks.sh \
        tools/fixture-textconv.txt \
        tools/fixture-binary.txt \
        tools/.gitattributes
    git -C "$fixture" -c core.hooksPath=/dev/null commit --no-verify -qm baseline
    GIT_INDEX_FILE="$fixture_index" git -C "$fixture" read-tree HEAD

    linked_fixture="$fixture-linked"
    git -C "$fixture" worktree add --detach -q "$linked_fixture" HEAD
    [[ ! -e "$fixture/.git/hooks/pre-commit" ]] || fail 'fixture shared hook unexpectedly exists before linked-worktree check'
    if output="$(cd /tmp && "$linked_fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'linked-worktree shared hook unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'inside the shared Git directory'; then
        printf '%s\n' "$output" >&2
        fail 'linked-worktree shared hook rejection was not explicit'
    fi
    if output="$(cd /tmp && "$linked_fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'linked-worktree shared hook unexpectedly installed'
    fi
    [[ ! -e "$fixture/.git/hooks/pre-commit" ]] || fail 'linked-worktree installer created a shared hook'
    printf '[PASS] installer rejects the common hooks directory for linked worktrees\n'

    shared_custom_hooks="$fixture_physical/.git/custom-hooks"
    git -C "$linked_fixture" config core.hooksPath "$shared_custom_hooks"
    [[ ! -e "$shared_custom_hooks" ]] || fail 'fixture shared custom hooks directory unexpectedly exists before check'
    if output="$(cd /tmp && "$linked_fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'linked-worktree custom shared hook path unexpectedly installed'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'inside the shared Git directory'; then
        printf '%s\n' "$output" >&2
        fail 'linked-worktree custom shared path rejection was not explicit'
    fi
    [[ ! -e "$shared_custom_hooks" ]] || fail 'linked-worktree custom shared path installer created a directory'
    git -C "$fixture" config --unset-all core.hooksPath || true
    printf '[PASS] installer rejects custom paths inside the shared Git directory\n'

    external_hooks_parent="$(mktemp -d "$temp_root/medcue-precommit-external-hooks.XXXXXX")"
    external_hooks_link="$external_hooks_parent/link-to-common-git"
    ln -s "$fixture_physical/.git" "$external_hooks_link"
    git -C "$fixture" config core.hooksPath "$external_hooks_link"
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'external symlink to the common Git directory unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'symbolic-link component'; then
        printf '%s\n' "$output" >&2
        fail 'external common-Git symlink rejection was not explicit'
    fi
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'external symlink to the common Git directory unexpectedly installed'
    fi
    [[ ! -e "$fixture_physical/.git/pre-commit" ]] || fail 'external common-Git symlink installer wrote a shared hook'
    git -C "$fixture" config --unset-all core.hooksPath || true
    printf '[PASS] installer rejects an external symlink to the common Git directory\n'

    fixture_reset_index() {
        GIT_INDEX_FILE="$fixture_index" git -C "$fixture" read-tree HEAD
    }

    fixture_stage() {
        GIT_INDEX_FILE="$fixture_index" git -C "$fixture" add -- "$@"
    }

    fixture_restore_policy_and_builder() {
        cp -p "$CONFIG_FILE" "$fixture/tools/pre-commit-checks.json"
        cp -p "$ROOT_DIR/tools/build-source-package.py" "$fixture/tools/build-source-package.py"
    }

    fixture_check() {
        (
            cd "$fixture"
            GIT_INDEX_FILE="$fixture_index" "$fixture/tools/run-pre-commit-checks.sh"
        )
    }

    fixture_policy_variant() {
        local variant="$1"
        python3 - "$fixture/tools/pre-commit-checks.json" "$variant" <<'PY'
import json
import sys

path, variant = sys.argv[1:3]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
policy = data["policy"]
if variant == "disable-json":
    policy["syntaxExtensions"] = [".js"]
elif variant == "empty-syntax":
    policy["syntaxExtensions"] = []
elif variant == "nul-prefix":
    policy["sourcePackageAllowlist"]["prefixes"].append("\x00/")
elif variant == "extra-prefix":
    policy["sourcePackageAllowlist"]["prefixes"].append("outside/")
elif variant == "bad-pattern-type":
    policy["absolutePathPatterns"] = [{}]
elif variant == "empty-prefix":
    policy["sourcePackageAllowlist"]["prefixes"].append("")
else:
    raise SystemExit(f"unknown fixture policy variant: {variant}")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
    }

    fixture_builder_drift() {
        python3 - "$fixture/tools/build-source-package.py" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = '    "ATTRIBUTION.md",\n'
if needle not in source:
    raise SystemExit("fixture builder anchor is missing")
source = source.replace(needle, needle + '    "fixture-drift.txt",\n', 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    }

    fixture_builder_empty_prefix() {
        python3 - "$fixture/tools/build-source-package.py" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = "ALLOWED_PREFIXES = (\n"
if needle not in source:
    raise SystemExit("fixture prefix anchor is missing")
source = source.replace(needle, needle + '    "",\n', 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    }

    fixture_expect_failure() {
        local label="$1" expected="$2"
        if output="$(fixture_check 2>&1)"; then
            fail "fixture unexpectedly passed: $label"
        fi
        if ! printf '%s\n' "$output" | grep -Fq -- "$expected"; then
            printf '%s\n' "$output" >&2
            fail "fixture failure did not contain '$expected': $label"
        fi
        printf '[PASS] fixture rejection: %s\n' "$label"
    }

    fixture_expect_success() {
        local label="$1"
        if ! output="$(fixture_check 2>&1)"; then
            printf '%s\n' "$output" >&2
            fail "fixture unexpectedly failed: $label"
        fi
        printf '[PASS] fixture acceptance: %s\n' "$label"
    }

    fixture_reset_index
    conflict_sha="$(git -C "$fixture" rev-parse HEAD:tools/fixture-textconv.txt)"
    printf '100644 %s 1\ttools/fixture-textconv.txt\n100644 %s 2\ttools/fixture-textconv.txt\n' \
        "$conflict_sha" "$conflict_sha" |
        GIT_INDEX_FILE="$fixture_index" git -C "$fixture" update-index --index-info
    fixture_expect_failure 'unmerged index entries fail closed' 'contains unmerged entries'

    fake_local_path="$(printf '/%s/fake-local-path' Users)"
    fixture_reset_index
    printf '%s\n' "+$fake_local_path" >"$fixture/tools/fixture-plus.txt"
    fixture_stage tools/fixture-plus.txt
    fixture_expect_failure 'leading-plus absolute path' 'absolute local path in added staged content'

    fake_bin="$fixture/fake-bin"
    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$fake_bin/grep"
    chmod +x "$fake_bin/grep"
    fixture_reset_index
    printf '%s\n' "$fake_local_path" >"$fixture/tools/fixture-fake-grep.txt"
    fixture_stage tools/fixture-fake-grep.txt
    if ! output="$(PATH="$fake_bin:$PATH" fixture_check 2>&1)"; then
        if ! printf '%s\n' "$output" | grep -Fq -- 'absolute local path in added staged content'; then
            printf '%s\n' "$output" >&2
            fail 'absolute path scan did not reject a path when grep was shadowed'
        fi
    else
        printf '%s\n' "$output" >&2
        fail 'absolute path scan passed when grep was shadowed'
    fi
    printf '[PASS] absolute path scan does not trust a shadowed grep\n'

    textconv_script="$fixture/tools/fixture-textconv.sh"
    textconv_marker="$fixture/textconv-invoked"
    printf '%s\n' '#!/bin/sh' "touch '$textconv_marker'" 'printf sanitized-textconv-output' >"$textconv_script"
    chmod +x "$textconv_script"
    printf '%s\n' '*.txt diff=fixture-hide' >"$fixture/.git/info/attributes"
    git -C "$fixture" config diff.fixture-hide.textconv "$textconv_script"
    fixture_reset_index
    printf '%s\n' "$fake_local_path" >"$fixture/tools/fixture-textconv.txt"
    fixture_stage tools/fixture-textconv.txt
    fixture_expect_failure 'staged blob bypasses local textconv' 'absolute local path in added staged content'
    [[ ! -e "$textconv_marker" ]] || fail 'textconv driver was invoked while checking the staged blob'

    fixture_reset_index
    printf '%s\n' "$fake_local_path" >"$fixture/tools/fixture-binary.txt"
    fixture_stage tools/fixture-binary.txt
    fixture_expect_failure 'binary attribute bypasses path scan' 'absolute local path in added staged content'

    fixture_reset_index
    printf 'prefix\0%s\n' "$fake_local_path" >"$fixture/tools/fixture-binary.txt"
    fixture_stage tools/fixture-binary.txt
    fixture_expect_failure 'NUL binary content does not hide an absolute path' 'absolute local path in added staged content'

    fixture_reset_index
    printf '%s\n' '{' >"$fixture/tools/fixture-invalid.json"
    fixture_stage tools/fixture-invalid.json
    fixture_expect_failure 'default JSON syntax policy' 'JSON syntax: tools/fixture-invalid.json'

    fixture_reset_index
    fixture_policy_variant disable-json
    fixture_stage tools/fixture-invalid.json
    fixture_expect_failure 'unstaged syntax policy is ignored' 'JSON syntax: tools/fixture-invalid.json'
    fixture_stage tools/pre-commit-checks.json
    fixture_expect_success 'staged syntax policy disables JSON parsing'

    fixture_reset_index
    fixture_restore_policy_and_builder
    fixture_policy_variant empty-syntax
    fixture_stage tools/pre-commit-checks.json
    fixture_expect_failure 'empty staged syntax extension list' 'syntaxExtensions must be a non-empty list without duplicates'

    fixture_reset_index
    fixture_restore_policy_and_builder
    fixture_policy_variant extra-prefix
    fixture_stage tools/pre-commit-checks.json
    fixture_expect_failure 'staged policy/source builder drift' 'source-package prefix policy drift'

    fixture_reset_index
    fixture_policy_variant bad-pattern-type
    fixture_stage tools/pre-commit-checks.json
    fixture_expect_failure 'invalid staged policy value type' 'absolutePathPatterns must be a non-empty list'

    fixture_reset_index
    fixture_restore_policy_and_builder
    fixture_policy_variant empty-prefix
    fixture_stage tools/pre-commit-checks.json
    fixture_expect_failure 'empty staged policy prefix' 'contains an empty or absolute path'

    fixture_reset_index
    fixture_restore_policy_and_builder
    fixture_policy_variant nul-prefix
    fixture_stage tools/pre-commit-checks.json
    fixture_expect_failure 'NUL staged policy prefix' 'contains a non-string or control character'

    fixture_reset_index
    fixture_restore_policy_and_builder
    fixture_builder_empty_prefix
    fixture_stage tools/build-source-package.py
    fixture_expect_failure 'empty staged builder prefix' 'contains an empty or absolute path'

    fixture_reset_index
    fixture_restore_policy_and_builder
    fixture_builder_drift
    fixture_stage tools/build-source-package.py
    fixture_expect_failure 'staged source builder/policy drift' 'source-package root-file policy drift'

    fixture_reset_index
    git -C "$fixture" config core.hooksPath .fixture-hooks
    [[ ! -e "$fixture/.fixture-hooks" ]] || fail "fixture hooks directory unexpectedly exists before read-only check"
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'read-only installer check unexpectedly passed before installation'
    fi
    [[ ! -e "$fixture/.fixture-hooks" ]] || fail 'read-only installer check created the hooks directory'
    printf '[PASS] installer --check is read-only for a relative hooks path\n'

    git -C "$fixture" config core.hooksPath 'foo/..'
    [[ ! -e "$fixture/pre-commit" ]] || fail 'fixture root pre-commit unexpectedly exists before normalized-root check'
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'normalized-root hooks path unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'disabled or resolves to the repository root'; then
        printf '%s\n' "$output" >&2
        fail 'normalized-root hooks path rejection was not explicit'
    fi
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'normalized-root hooks path unexpectedly installed a repository-root hook'
    fi
    [[ ! -e "$fixture/pre-commit" ]] || fail 'normalized-root hooks path installation created a repository-root hook'
    printf '[PASS] installer rejects a normalized path resolving to the repository root\n'

    ln -s "$fixture" "$fixture/link-root"
    git -C "$fixture" config core.hooksPath link-root
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'symlinked-root hooks path unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'disabled or resolves to the repository root'; then
        printf '%s\n' "$output" >&2
        fail 'symlinked-root hooks path rejection was not explicit'
    fi
    [[ ! -e "$fixture/pre-commit" ]] || fail 'symlinked-root hooks path check created a repository-root hook'
    printf '[PASS] installer rejects a symlinked path resolving to the repository root\n'

    absolute_hooks="$fixture/.absolute-hooks"
    git -C "$fixture" config core.hooksPath "$absolute_hooks"
    [[ ! -e "$absolute_hooks" ]] || fail 'absolute fixture hooks directory unexpectedly exists before installation'
    if ! output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail 'installer failed for an absolute hooks path from outside the repository'
    fi
    absolute_hook_path="$absolute_hooks/pre-commit"
    [[ -f "$absolute_hook_path" && -x "$absolute_hook_path" ]] || fail "absolute fixture hook is missing or not executable: $absolute_hook_path"
    if ! output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail 'absolute fixture hook did not pass --check'
    fi
    printf '[PASS] installer resolves and verifies an absolute hooks path outside the repository\n'

    symlink_target="$fixture_physical/.symlink-hook-target"
    symlink_hooks="$fixture_physical/.symlink-hook-path"
    mkdir -p "$symlink_target"
    ln -s "$symlink_target" "$symlink_hooks"
    git -C "$fixture" config core.hooksPath .symlink-hook-path
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'relative symlink hooks path unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'symbolic-link component'; then
        printf '%s\n' "$output" >&2
        fail 'relative symlink hooks path rejection was not explicit'
    fi
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'relative symlink hooks path unexpectedly installed'
    fi
    [[ ! -e "$symlink_target/pre-commit" ]] || fail 'relative symlink hooks path wrote into its target'
    printf '[PASS] installer rejects a relative symlink hooks directory\n'

    absolute_symlink_target="$fixture_physical/.absolute-symlink-hook-target"
    absolute_symlink_hooks="$fixture_physical/.absolute-symlink-hook-path"
    mkdir -p "$absolute_symlink_target"
    ln -s "$absolute_symlink_target" "$absolute_symlink_hooks"
    git -C "$fixture" config core.hooksPath "$absolute_symlink_hooks"
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'absolute symlink hooks path unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'symbolic-link component'; then
        printf '%s\n' "$output" >&2
        fail 'absolute symlink hooks path rejection was not explicit'
    fi
    [[ ! -e "$absolute_symlink_target/pre-commit" ]] || fail 'absolute symlink hooks path wrote into its target'
    printf '[PASS] installer rejects an absolute symlink hooks directory\n'

    git -C "$fixture" config core.hooksPath .symlink-hooks
    mkdir -p "$fixture/.symlink-hooks"
    ln -s "$fixture/tools/run-pre-commit-checks.sh" "$fixture/.symlink-hooks/pre-commit"
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'symbolic-link hook unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'exact managed MedCue hook'; then
        printf '%s\n' "$output" >&2
        fail 'symbolic-link hook rejection did not use the exact-content diagnostic'
    fi
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'installer unexpectedly replaced a symbolic-link hook'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'symbolic-link hook'; then
        printf '%s\n' "$output" >&2
        fail 'symbolic-link hook install rejection was not explicit'
    fi
    printf '[PASS] installer rejects symbolic-link hooks\n'

    git -C "$fixture" config core.hooksPath .nonregular-hooks
    mkdir -p "$fixture/.nonregular-hooks/pre-commit"
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'installer unexpectedly replaced a non-regular hook path'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'non-regular hook'; then
        printf '%s\n' "$output" >&2
        fail 'non-regular hook install rejection was not explicit'
    fi
    printf '[PASS] installer rejects non-regular hooks\n'

    git -C "$fixture" config core.hooksPath ''
    [[ ! -e "$fixture/pre-commit" ]] || fail 'fixture root pre-commit unexpectedly exists before disabled-path check'
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'disabled hooks path unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'disabled or cannot be resolved'; then
        printf '%s\n' "$output" >&2
        fail 'disabled hooks path rejection did not explain the safe failure'
    fi
    [[ ! -e "$fixture/pre-commit" ]] || fail 'disabled hooks path check created a repository-root hook'
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        fail 'disabled hooks path unexpectedly installed a repository-root hook'
    fi
    [[ ! -e "$fixture/pre-commit" ]] || fail 'disabled hooks path installation created a repository-root hook'
    printf '[PASS] installer fails closed for a disabled/root hooks path\n'

    git -C "$fixture" config core.hooksPath .fixture-hooks
    if ! output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail 'installer failed from outside the repository root'
    fi
    hook_path="$fixture/.fixture-hooks/pre-commit"
    [[ -f "$hook_path" && -x "$hook_path" ]] || fail "installed fixture hook is missing or not executable: $hook_path"
    if ! output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail 'exact managed fixture hook did not pass --check'
    fi
    printf '[PASS] installer resolves and verifies a relative hooks path outside the repository\n'

    hardlink_hooks="$fixture/.hardlink-hooks"
    hardlink_target="$fixture/hardlink-target.txt"
    mkdir -p "$hardlink_hooks"
    printf '%s\n' 'DO NOT OVERWRITE' >"$hardlink_target"
    ln "$hardlink_target" "$hardlink_hooks/pre-commit"
    git -C "$fixture" config core.hooksPath .hardlink-hooks
    if ! output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail 'installer failed while replacing a hard-linked hook'
    fi
    [[ "$(<"$hardlink_target")" == 'DO NOT OVERWRITE' ]] ||
        fail 'atomic hook installation modified a hard-linked target'
    [[ -f "$hardlink_hooks/pre-commit" && -x "$hardlink_hooks/pre-commit" ]] ||
        fail 'atomic hook installation did not create an executable managed hook'
    printf '[PASS] installer preserves hard-linked hook targets\n'
    git -C "$fixture" config core.hooksPath .fixture-hooks

    fixture_reset_index
    printf '%s\n' 'unsafe staged path' >"$fixture/unsafe.txt"
    fixture_stage unsafe.txt
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$fixture/tools/run-pre-commit-checks.sh"
    if output="$(cd "$fixture" && GIT_INDEX_FILE="$fixture_index" "$hook_path" 2>&1)"; then
        fail 'managed hook executed the unchecked working-tree checker'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'outside the source-package allowlist'; then
        printf '%s\n' "$output" >&2
        fail 'managed hook did not execute the staged checker'
    fi
    cp -p "$CHECKER" "$fixture/tools/run-pre-commit-checks.sh"
    printf '[PASS] managed hook executes the staged checker blob\n'

    printf '%s\n' '# medcue-pre-commit-managed' >"$hook_path"
    chmod +x "$hook_path"
    if output="$(cd /tmp && "$fixture/tools/install-hooks.sh" --check 2>&1)"; then
        fail 'marker-only hook spoof unexpectedly passed installer --check'
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- 'exact managed MedCue hook'; then
        fail 'marker-only hook rejection did not identify exact managed content'
    fi
    if ! output="$(cd /tmp && "$fixture/tools/install-hooks.sh" 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail 'installer did not repair marker-only hook spoof'
    fi
    backup_count="$(find "$fixture/.fixture-hooks" -maxdepth 1 -type f -name 'pre-commit.backup.*' | wc -l | tr -d ' ')"
    [[ "$backup_count" -ge 1 ]] || fail 'installer did not preserve the replaced hook backup'
    printf '[PASS] installer rejects and repairs a marker-only hook spoof\n'

    printf 'pre-commit fixture retained for inspection: %s\n' "$fixture"
}

run_fixture_boundary_tests

printf '%s\n' 'pre-commit system checks passed'

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

git -C "$ROOT_DIR" diff --cached --check
"$CHECKER"

printf '%s\n' 'pre-commit system checks passed'

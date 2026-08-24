#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/native-verification-classifier.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

cd "$TEST_ROOT"
git init -q
git config user.name "native-verification-test"
git config user.email "native-verification-test@example.invalid"
mkdir -p docs cloudfunctions/medcue-ai-broker/src ios-app .github/ISSUE_TEMPLATE .github/workflows
printf 'synthetic documentation\n' > docs/guide.md
printf 'synthetic broker source\n' > cloudfunctions/medcue-ai-broker/src/broker.js
printf 'synthetic native source\n' > ios-app/App.swift
git add .
git commit -qm "synthetic base"
BASE_SHA="$(git rev-parse HEAD)"

reset_case() {
  git checkout -q -B case "$BASE_SHA"
  git clean -fdx -q
}

commit_case() {
  git add -A
  git commit -qm "$1"
}

expect_lane() {
  local expected_lane="$1"
  local case_name="$2"
  shift 2
  local head_sha
  local output
  local lane

  head_sha="$(git rev-parse HEAD)"
  output="$("$CLASSIFIER" --base "$BASE_SHA" --head "$head_sha" --event pull_request --ref refs/pull/1/merge --forced false "$@")"
  lane="$(printf '%s\n' "$output" | awk -F= '$1 == "lane" { print $2 }')"
  [[ "$lane" == "$expected_lane" ]] || {
    printf 'case %s expected lane %s, got %s\n' "$case_name" "$expected_lane" "$lane" >&2
    exit 1
  }
}

expect_failure() {
  local case_name="$1"
  shift
  if "$CLASSIFIER" "$@" >/dev/null 2>&1; then
    printf 'case %s unexpectedly succeeded\n' "$case_name" >&2
    exit 1
  fi
}

reset_case
printf 'updated synthetic documentation\n' > docs/guide.md
commit_case "docs change"
expect_lane docs docs-only

reset_case
printf 'updated synthetic broker source\n' > cloudfunctions/medcue-ai-broker/src/broker.js
commit_case "broker change"
expect_lane broker broker-only

reset_case
printf '{"name":"synthetic-broker"}\n' > cloudfunctions/medcue-ai-broker/package.json
mkdir -p cloudfunctions/medcue-ai-broker/deep/nested
printf 'deep broker source\n' > cloudfunctions/medcue-ai-broker/deep/nested/README.md
commit_case "broker metadata and deep path change"
expect_lane broker broker-deep-path

reset_case
printf '{invalid-json}\n' > cloudfunctions/medcue-ai-broker/package.json
commit_case "invalid broker metadata"
expect_lane broker broker-invalid-metadata

reset_case
printf 'updated synthetic native source\n' > ios-app/App.swift
commit_case "native change"
expect_lane full native-only

reset_case
mkdir -p .github/workflows
printf 'name: synthetic\n' > .github/workflows/extra.yml
commit_case "workflow change"
expect_lane full workflow-change

reset_case
printf 'mixed change\n' > docs/mixed.md
printf 'mixed broker change\n' > cloudfunctions/medcue-ai-broker/src/mixed.js
commit_case "mixed change"
expect_lane full mixed-change

reset_case
printf 'unknown change\n' > unknown.bin
commit_case "unknown change"
expect_lane full unknown-change

reset_case
git mv docs/guide.md docs/renamed.md
commit_case "docs rename"
expect_lane docs docs-rename

reset_case
rm docs/guide.md
commit_case "docs deletion"
expect_lane docs docs-deletion

reset_case
rm cloudfunctions/medcue-ai-broker/src/broker.js
commit_case "broker deletion"
expect_lane broker broker-deletion

reset_case
printf 'main documentation change\n' > docs/main.md
commit_case "main documentation change"
head_sha="$(git rev-parse HEAD)"
output="$("$CLASSIFIER" --base "$BASE_SHA" --head "$head_sha" --event push --ref refs/heads/main --forced false)"
[[ "$(printf '%s\n' "$output" | awk -F= '$1 == "lane" { print $2 }')" == full ]]
[[ "$(printf '%s\n' "$output" | awk -F= '$1 == "full_tree" { print $2 }')" == 1 ]]
EMPTY_TREE="$(git hash-object -w -t tree /dev/null)"
[[ "$(printf '%s\n' "$output" | awk -F= '$1 == "diff_base" { print $2 }')" == "$EMPTY_TREE" ]]

reset_case
printf 'main documentation change after a forced update\n' > docs/main-forced.md
commit_case "forced main documentation change"
head_sha="$(git rev-parse HEAD)"
output="$("$CLASSIFIER" --base "$BASE_SHA" --head "$head_sha" --event push --ref refs/heads/main --forced true)"
[[ "$(printf '%s\n' "$output" | awk -F= '$1 == "lane" { print $2 }')" == full ]]
[[ "$(printf '%s\n' "$output" | awk -F= '$1 == "full_tree" { print $2 }')" == 1 ]]
[[ "$(printf '%s\n' "$output" | awk -F= '$1 == "diff_base" { print $2 }')" == "$EMPTY_TREE" ]]

expect_failure invalid-head --base "$BASE_SHA" --head not-a-sha --event pull_request --ref refs/pull/1/merge --forced false
expect_failure invalid-main-base --base not-a-sha --head "$head_sha" --event push --ref refs/heads/main --forced false
expect_failure self-diff --base "$head_sha" --head "$head_sha" --event pull_request --ref refs/pull/1/merge --forced false
expect_failure missing-base --base 1111111111111111111111111111111111111111 --head "$head_sha" --event pull_request --ref refs/pull/1/merge --forced false
expect_failure invalid-event --base "$BASE_SHA" --head "$head_sha" --event unknown --ref refs/pull/1/merge --forced false
expect_failure all-zero-pull-request --base 0000000000000000000000000000000000000000 --head "$head_sha" --event pull_request --ref refs/pull/1/merge --forced false

printf 'native-verification-classifier matrix passed\n'

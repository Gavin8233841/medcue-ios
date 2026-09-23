#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage: tools/native-verification-classifier.sh \
  --base <full commit SHA> \
  --head <full commit SHA> \
  --event <pull_request|push|workflow_dispatch> \
  --ref <GitHub ref> \
  --forced <true|false>

Prints lane, diff_base, full_tree, changed_files, and head as GitHub output lines.
USAGE
}

fail() {
  printf 'native-verification-classifier: %s\n' "$*" >&2
  exit 2
}

base_sha=""
head_sha=""
event_name=""
ref_name=""
forced=""

while (($# > 0)); do
  case "$1" in
    --base)
      (($# >= 2)) || fail "--base requires a value"
      base_sha="$2"
      shift 2
      ;;
    --head)
      (($# >= 2)) || fail "--head requires a value"
      head_sha="$2"
      shift 2
      ;;
    --event)
      (($# >= 2)) || fail "--event requires a value"
      event_name="$2"
      shift 2
      ;;
    --ref)
      (($# >= 2)) || fail "--ref requires a value"
      ref_name="$2"
      shift 2
      ;;
    --forced)
      (($# >= 2)) || fail "--forced requires a value"
      forced="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || fail "base must be a full lowercase commit SHA"
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || fail "head must be a full lowercase commit SHA"
[[ -n "$ref_name" ]] || fail "ref is required"
[[ "$forced" == true || "$forced" == false ]] || fail "forced must be true or false"

case "$event_name" in
  pull_request|push|workflow_dispatch) ;;
  *) fail "unsupported event: $event_name" ;;
esac

if [[ "$event_name" == push && "$ref_name" != refs/heads/main ]]; then
  fail "push verification is permitted only for refs/heads/main"
fi

remove_checkout_credentials() {
  local credential_key
  while IFS= read -r credential_key; do
    [[ -n "$credential_key" ]] || continue
    git config --local --unset-all "$credential_key" || true
  done < <(git config --local --name-only --get-regexp '^http\..*\.extraheader$' || true)
  git config --local --unset-all core.sshCommand || true
}

trap remove_checkout_credentials EXIT
export GIT_TERMINAL_PROMPT=0

actual_head="$(git rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" ||
  fail "checked-out HEAD is not a commit"
[[ "$actual_head" == "$head_sha" ]] ||
  fail "checked-out HEAD does not match the requested head"

zero_sha="0000000000000000000000000000000000000000"
empty_tree="$(git hash-object -w -t tree /dev/null)"
full_tree=0
if [[ "$base_sha" == "$zero_sha" ]]; then
  [[ "$event_name" == push && "$ref_name" == refs/heads/main ]] ||
    fail "the all-zero base is valid only for a push to main"
  full_tree=1
elif [[ "$base_sha" == "$head_sha" ]]; then
  fail "base must differ from head; refusing a self-diff"
elif ! git cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
  git fetch --no-tags --no-recurse-submodules --depth=1 origin "$base_sha" ||
    fail "unable to fetch the requested base commit"
  fetched_sha="$(git rev-parse --verify 'FETCH_HEAD^{commit}' 2>/dev/null)" ||
    fail "fetched base is not a commit"
  [[ "$fetched_sha" == "$base_sha" ]] ||
    fail "fetched base does not match the requested base"
  git cat-file -e "${base_sha}^{commit}" || fail "requested base commit is unavailable"
fi

# Every push to the authoritative main ref is a complete-tree verification.
# The event's before SHA is still resolved above so an invalid or unavailable
# base cannot silently bypass the input contract; the lane compares against
# the empty tree to cover the entire resulting main tree.
if [[ "$event_name" == push && "$ref_name" == refs/heads/main ]]; then
  full_tree=1
fi

if [[ "$full_tree" == 1 ]]; then
  lane="full"
  diff_base="$empty_tree"
  changed_files="full-tree"
else
  diff_fields=()
  while IFS= read -r -d '' diff_field; do
    diff_fields+=("$diff_field")
  done < <(git diff --name-status --find-renames=50% -z "$base_sha" "$head_sha")

  paths=()
  field_index=0
  while ((field_index < ${#diff_fields[@]})); do
    status="${diff_fields[field_index]}"
    ((field_index += 1))
    [[ -n "$status" ]] || fail "empty diff status"
    case "${status:0:1}" in
      R|C)
        ((field_index + 1 < ${#diff_fields[@]})) || fail "rename diff is missing a path"
        paths+=("${diff_fields[field_index]}")
        ((field_index += 1))
        paths+=("${diff_fields[field_index]}")
        ((field_index += 1))
        ;;
      *)
        ((field_index < ${#diff_fields[@]})) || fail "diff status is missing a path"
        paths+=("${diff_fields[field_index]}")
        ((field_index += 1))
        ;;
    esac
  done

  is_docs_path() {
    case "$1" in
      docs/*|README.md|CHANGELOG.md|LICENSE|LICENSE.*|CODE_OF_CONDUCT.md|CONTRIBUTING.md|.github/ISSUE_TEMPLATE/*|.github/pull_request_template.md|.github/GITHUB_LOCALIZATION.md)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  is_broker_path() {
    [[ "$1" == cloudfunctions/medcue-ai-broker/* ]]
  }

  is_swift_core_only_path() {
    case "$1" in
      swift-core/*|Package.swift|Package.resolved)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  is_watch_only_path() {
    case "$1" in
      ios-app/MedicationAdherenceApp/MedicationAdherenceWatchApp/*|ios-app/MedicationAdherenceApp/MedicationAdherenceWatchWidget/*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  is_full_path() {
    case "$1" in
      .github/workflows/*|tools/*|ios-app/*|swift-core/*|Package.swift|Package.resolved|*.xcodeproj/*|*.xcworkspace/*|*.pbxproj|*.xcconfig|*.entitlements|*.xcscheme|*.plist)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  all_docs=1
  all_broker=1
  all_swift_core_only=1
  all_watch_only=1
  contains_full_path=0
  for path in "${paths[@]}"; do
    is_docs_path "$path" || all_docs=0
    is_broker_path "$path" || all_broker=0
    is_swift_core_only_path "$path" || all_swift_core_only=0
    is_watch_only_path "$path" || all_watch_only=0
    is_full_path "$path" && contains_full_path=1
  done

  if ((${#paths[@]} == 0)) || ((contains_full_path == 1)); then
    lane="full"
  elif ((all_broker == 1)); then
    lane="broker"
  elif ((all_docs == 1)); then
    lane="docs"
  elif ((all_swift_core_only == 1)); then
    lane="swift-core-only"
  elif ((all_watch_only == 1)); then
    lane="watch-only"
  else
    lane="full"
  fi
  changed_files="${#paths[@]}"
fi

remove_checkout_credentials
trap - EXIT
if git config --local --name-only --list | grep -Eiq '^(http\..*\.extraheader|core\.sshcommand)$'; then
  fail "checkout credentials remain in local Git configuration"
fi

printf 'lane=%s\n' "$lane"
printf 'diff_base=%s\n' "${diff_base:-$base_sha}"
printf 'full_tree=%s\n' "$full_tree"
printf 'changed_files=%s\n' "$changed_files"
printf 'head=%s\n' "$head_sha"

#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj"
XCODE_PROJECT="$ROOT_DIR/ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj"
SWIFT_CORE_DIR="$ROOT_DIR/swift-core"
PREFLIGHT_SCRIPT="$ROOT_DIR/tools/ios-preflight-check.sh"
SOURCE_SIZE_SCRIPT="$ROOT_DIR/tools/swift-source-size-check.sh"
SOURCE_PACKAGE_BUILDER="$ROOT_DIR/tools/build-source-package.py"
SOURCE_PACKAGE_TESTS="$ROOT_DIR/tools/test-source-package.py"
SOURCE_PACKAGE_VERIFIER="$ROOT_DIR/tools/verify-source-package.py"

MAIN_APP_TARGET="MedicationAdherenceApp"
IOS_TEST_SCHEME="MedicationAdherenceApp"
IOS_TEST_TARGET="MedicationAdherenceAppTests"
IOS_UI_TEST_TARGET="MedicationAdherenceAppUITests"
WATCH_APP_TARGET="MedicationAdherenceWatchApp"
WATCH_SIMULATOR_SDK="${VERIFY_NATIVE_WATCH_SIMULATOR_SDK:-watchsimulator26.5}"
WATCH_DEVICE_SDK="${VERIFY_NATIVE_WATCH_DEVICE_SDK:-watchos26.5}"
IOS_TEST_DESTINATION="${VERIFY_NATIVE_IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5}"

CURRENT_STEP="startup"
CHECKS_ONLY="${VERIFY_NATIVE_CHECKS_ONLY:-0}"
VERIFICATION_ROOT=""

usage() {
    cat <<'USAGE'
Usage: tools/verify-native.sh [--quick]

Runs the Route A native verification gate from the repository root.

Options:
  --quick  Run non-build checks only. This never changes the default full gate.
  --help   Show this help.

Environment:
  VERIFY_NATIVE_CHECKS_ONLY=1
             Run non-build checks only (the same behavior as --quick).
  VERIFY_NATIVE_DIFF_BASE=<full-commit-sha>
             Also check the complete committed tree difference from this exact
             40-character commit through HEAD. CI sets this to the Pull Request
             base or the pre-push revision.
  VERIFY_NATIVE_FULL_TREE=1
             Check every file in HEAD from the empty tree. CI permits this only
             for a new or explicitly forced push to main.
  VERIFY_NATIVE_ROOT=<path>
             Reusable build root. It must resolve inside this repository and
             already be covered by .gitignore. The default is
             .codex-local/native-verification.
  VERIFY_NATIVE_IOS_TEST_DESTINATION=<xcodebuild destination>
             Override the iOS Simulator used for hosted unit tests. The default
             is platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5.
  VERIFY_NATIVE_WATCH_SIMULATOR_SDK=<sdk>
             Override the Watch Simulator SDK name. The default is
             watchsimulator26.5.
  VERIFY_NATIVE_WATCH_DEVICE_SDK=<sdk>
             Override the Watch device SDK name. The default is watchos26.5.
USAGE
}

fail() {
    printf 'verify-native: %s\n' "$*" >&2
    exit 2
}

on_error() {
    local status=$?
    printf '\n[FAIL] %s (exit %d)\n' "$CURRENT_STEP" "$status" >&2
    exit "$status"
}
trap on_error ERR

run_step() {
    local label="$1"
    shift
    CURRENT_STEP="$label"
    printf '\n== %s ==\n' "$label"
    "$@"
}

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
}

require_file() {
    local path="$1"
    [[ -f "$path" ]] || fail "required file not found: $path"
}

assert_verification_directory() {
    local directory="$1"
    local label="$2"
    local resolved_directory

    case "$directory" in
        "$VERIFICATION_ROOT"/*) ;;
        *) fail "$label is outside VERIFY_NATIVE_ROOT: $directory" ;;
    esac
    [[ ! -L "$directory" ]] || fail "$label must not be a symbolic link: $directory"
    [[ -d "$directory" ]] || fail "$label not found: $directory"
    resolved_directory="$(realpath "$directory")" ||
        fail "$label cannot be resolved: $directory"
    case "$resolved_directory" in
        "$VERIFICATION_ROOT"/*) ;;
        *) fail "$label resolves outside VERIFY_NATIVE_ROOT: $directory" ;;
    esac
}

assert_verification_tree_safe() {
    local symbolic_link
    local resolved_link

    [[ -n "$VERIFICATION_ROOT" && -d "$VERIFICATION_ROOT" ]] || return
    if ! find -P "$VERIFICATION_ROOT" -type l -print0 | (
        while IFS= read -r -d '' symbolic_link; do
            resolved_link="$(realpath "$symbolic_link" 2>/dev/null)" || exit 1
            case "$resolved_link" in
                "$VERIFICATION_ROOT"|"$VERIFICATION_ROOT"/*) ;;
                *) exit 1 ;;
            esac
        done
    ); then
        fail "verification output contains an unresolvable or escaping symbolic link"
    fi
}

assert_symlinks_contained() {
    local directory="$1"
    local label="$2"
    local symbolic_link
    local resolved_link
    if ! find -P "$directory" -type l -print0 | (
        while IFS= read -r -d '' symbolic_link; do
            resolved_link="$(realpath "$symbolic_link" 2>/dev/null)" || exit 1
            case "$resolved_link" in
                "$directory"|"$directory"/*) ;;
                *) exit 1 ;;
            esac
        done
    ); then
        fail "$label contains an unresolvable or escaping symbolic link"
    fi
}

prepare_verification_directory() {
    local directory="$1"
    local label="$2"
    local existing_ancestor="$directory"
    local resolved_ancestor

    assert_verification_tree_safe
    case "$directory" in
        "$VERIFICATION_ROOT"/*) ;;
        *) fail "$label is outside VERIFY_NATIVE_ROOT: $directory" ;;
    esac
    [[ ! -L "$directory" ]] || fail "$label must not be a symbolic link: $directory"
    while [[ ! -e "$existing_ancestor" && ! -L "$existing_ancestor" ]]; do
        existing_ancestor="$(dirname "$existing_ancestor")"
    done
    [[ -d "$existing_ancestor" ]] ||
        fail "$label has a non-directory path component: $existing_ancestor"
    resolved_ancestor="$(realpath "$existing_ancestor")" ||
        fail "$label has an unresolvable path component: $existing_ancestor"
    case "$resolved_ancestor" in
        "$VERIFICATION_ROOT"|"$VERIFICATION_ROOT"/*) ;;
        *) fail "$label resolves outside VERIFY_NATIVE_ROOT before creation: $directory" ;;
    esac

    mkdir -p "$directory"
    assert_verification_directory "$directory" "$label"
    assert_verification_tree_safe
}

verify_git_diff() {
    local diff_base="${VERIFY_NATIVE_DIFF_BASE:-}"
    local ci_event="${VERIFY_NATIVE_CI_EVENT:-}"
    local ci_ref="${VERIFY_NATIVE_CI_REF:-}"
    local full_tree="${VERIFY_NATIVE_FULL_TREE:-0}"
    local head_sha
    local empty_tree

    head_sha="$(git rev-parse --verify HEAD)"
    echo "Verified head: $head_sha"

    git diff --check
    git diff --cached --check

    case "$full_tree" in
        0|1) ;;
        *) fail "VERIFY_NATIVE_FULL_TREE must be 0 or 1" ;;
    esac

    if [[ "$full_tree" == 1 ]]; then
        [[ "${CI:-}" == "true" && "$ci_event" == "push" && "$ci_ref" == "refs/heads/main" ]] ||
            fail "VERIFY_NATIVE_FULL_TREE is permitted only for a push to main in CI"
        empty_tree="$(git hash-object -w -t tree /dev/null)"
        [[ -z "$diff_base" || "$diff_base" == "$empty_tree" || "$diff_base" == "0000000000000000000000000000000000000000" ]] ||
            fail "VERIFY_NATIVE_DIFF_BASE must identify the empty tree in full-tree mode"
        echo "Checking committed full tree from: $empty_tree"
        git diff --check "$empty_tree" HEAD
        return
    fi

    if [[ "$diff_base" == "0000000000000000000000000000000000000000" ]]; then
        fail "VERIFY_NATIVE_DIFF_BASE cannot be the all-zero sentinel outside full-tree mode"
    fi

    if [[ -n "$diff_base" ]]; then
        [[ "$diff_base" =~ ^[0-9a-f]{40}$ ]] ||
            fail "VERIFY_NATIVE_DIFF_BASE must be a full 40-character lowercase commit SHA"
        [[ "$diff_base" != "$head_sha" ]] ||
            fail "VERIFY_NATIVE_DIFF_BASE must differ from HEAD; refusing a self-diff"
        if git rev-parse --verify --quiet "${diff_base}^{commit}" >/dev/null; then
            echo "Committed diff base: $diff_base"
            git diff --check "$diff_base" HEAD
            return
        fi
    fi

    if [[ -n "$diff_base" ]]; then
        fail "VERIFY_NATIVE_DIFF_BASE is not an available commit: $diff_base"
    elif [[ "${CI:-}" == "true" ]]; then
        fail "VERIFY_NATIVE_DIFF_BASE is required in CI"
    fi
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            --quick)
                CHECKS_ONLY=1
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                fail "unknown argument: $1"
                ;;
        esac
        shift
    done

    case "$CHECKS_ONLY" in
        0|1) ;;
        *) fail "VERIFY_NATIVE_CHECKS_ONLY must be 0 or 1" ;;
    esac
}

prepare_verification_root() {
    local requested_root="${VERIFY_NATIVE_ROOT:-.codex-local/native-verification}"
    local candidate_root
    local existing_ancestor
    local existing_ancestor_real
    local candidate_relative
    local resolved_root
    local resolved_relative

    [[ -n "$requested_root" ]] || fail "VERIFY_NATIVE_ROOT must not be empty"
    case "/$requested_root/" in
        *"/../"*|*"/./"*) fail "VERIFY_NATIVE_ROOT must not contain . or .. path components" ;;
    esac

    if [[ "$requested_root" == /* ]]; then
        candidate_root="${requested_root%/}"
    else
        candidate_root="$ROOT_DIR/${requested_root%/}"
    fi

    [[ "$candidate_root" != "$ROOT_DIR" ]] || fail "VERIFY_NATIVE_ROOT cannot be the repository root"
    case "$candidate_root" in
        "$ROOT_DIR"/*) ;;
        *) fail "VERIFY_NATIVE_ROOT must be inside $ROOT_DIR" ;;
    esac

    existing_ancestor="$candidate_root"
    while [[ ! -e "$existing_ancestor" && ! -L "$existing_ancestor" ]]; do
        existing_ancestor="$(dirname "$existing_ancestor")"
    done
    [[ ! -L "$existing_ancestor" ]] ||
        fail "VERIFY_NATIVE_ROOT has a symbolic-link path component: $existing_ancestor"
    existing_ancestor_real="$(realpath "$existing_ancestor")"
    case "$existing_ancestor_real" in
        "$ROOT_DIR"|"$ROOT_DIR"/*) ;;
        *) fail "VERIFY_NATIVE_ROOT resolves outside the repository through a symlink" ;;
    esac

    candidate_relative="${candidate_root#"$ROOT_DIR"/}"
    if ! git check-ignore -q -- "$candidate_relative/.verify-native-output"; then
        fail "VERIFY_NATIVE_ROOT is not covered by .gitignore: $candidate_relative"
    fi

    mkdir -p "$candidate_root"
    [[ -d "$candidate_root" ]] || fail "VERIFY_NATIVE_ROOT is not a directory: $candidate_root"
    resolved_root="$(realpath "$candidate_root")"
    case "$resolved_root" in
        "$ROOT_DIR"/*) ;;
        *) fail "VERIFY_NATIVE_ROOT resolved outside the repository" ;;
    esac

    resolved_relative="${resolved_root#"$ROOT_DIR"/}"
    if ! git check-ignore -q -- "$resolved_relative/.verify-native-output"; then
        fail "resolved VERIFY_NATIVE_ROOT is not covered by .gitignore: $resolved_relative"
    fi

    VERIFICATION_ROOT="$resolved_root"
    assert_verification_tree_safe
    prepare_verification_directory "$VERIFICATION_ROOT/tmp" "temporary output directory"
    prepare_verification_directory "$VERIFICATION_ROOT/module-cache/clang" "Clang module cache"
    prepare_verification_directory "$VERIFICATION_ROOT/module-cache/swift" "Swift module cache"
    prepare_verification_directory "$VERIFICATION_ROOT/swift-core/cache" "Swift package cache"
    prepare_verification_directory "$VERIFICATION_ROOT/swift-core/scratch" "Swift package scratch directory"
    prepare_verification_directory "$VERIFICATION_ROOT/source-packages" "cloned source packages directory"

    export TMPDIR="$VERIFICATION_ROOT/tmp"
    export CLANG_MODULE_CACHE_PATH="$VERIFICATION_ROOT/module-cache/clang"
    export SWIFT_MODULE_CACHE_PATH="$VERIFICATION_ROOT/module-cache/swift"
    export GIT_TERMINAL_PROMPT=0

    printf 'Verification root: %s\n' "$VERIFICATION_ROOT"
}

run_swift_core_tests() {
    swift test \
        --package-path "$SWIFT_CORE_DIR" \
        --cache-path "$VERIFICATION_ROOT/swift-core/cache" \
        --scratch-path "$VERIFICATION_ROOT/swift-core/scratch" \
        --manifest-cache none \
        --disable-dependency-cache \
        --disable-prefetching \
        --disable-automatic-resolution \
        --skip-update \
        --disable-netrc \
        --disable-keychain
    assert_verification_tree_safe
}

run_source_package_gate() {
    local revision
    local output_dir
    local package_path
    local digest_path
    local temp_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

    [[ -d "$temp_parent" ]] || fail "source-package temporary parent not found: $temp_parent"
    output_dir="$(mktemp -d "${temp_parent%/}/medcue-source-package.XXXXXX")"
    revision="$(git rev-parse --verify HEAD)"

    PYTHONDONTWRITEBYTECODE=1 python3 "$SOURCE_PACKAGE_TESTS"
    PYTHONDONTWRITEBYTECODE=1 python3 "$SOURCE_PACKAGE_BUILDER" \
        --revision "$revision" \
        --output-dir "$output_dir" \
        --repository "$ROOT_DIR"
    package_path="$output_dir/MedCue-source-${revision:0:12}.zip"
    digest_path="$package_path.sha256"
    PYTHONDONTWRITEBYTECODE=1 python3 "$SOURCE_PACKAGE_VERIFIER" "$package_path" "$digest_path"
    unzip -t "$package_path"
    printf 'Source-package evidence retained at: %s\n' "$output_dir"
}

run_xcode_build() {
    local target="$1"
    local configuration="$2"
    local output_name="$3"
    local sdk="${4:-}"
    local output_root="$VERIFICATION_ROOT/$output_name"
    local xcodebuild_arguments=(
        -project "$XCODE_PROJECT"
        -target "$target"
        -configuration "$configuration"
    )

    case "$output_name" in
        main-app-release|watch-simulator-debug|watch-device-release) ;;
        *) fail "unsupported Xcode output namespace: $output_name" ;;
    esac

    if [[ -n "$sdk" ]]; then
        xcodebuild_arguments+=(-sdk "$sdk")
    fi

    prepare_verification_directory "$output_root/products" "$output_name products directory"
    prepare_verification_directory "$output_root/objects" "$output_name objects directory"
    prepare_verification_directory "$output_root/symbols" "$output_name symbols directory"

    xcodebuild_arguments+=(
        -clonedSourcePackagesDirPath "$VERIFICATION_ROOT/source-packages"
        -disableAutomaticPackageResolution
        -skipPackageUpdates
        BUILD_DIR="$output_root/products"
        OBJROOT="$output_root/objects"
        SYMROOT="$output_root/symbols"
        CODE_SIGNING_ALLOWED=NO
        build
    )
    xcodebuild "${xcodebuild_arguments[@]}"
    assert_verification_tree_safe
}

run_ios_unit_tests() {
    local output_root="$VERIFICATION_ROOT/ios-unit-tests"

    prepare_verification_directory "$output_root/derived-data" "iOS unit-test derived data"
    xcodebuild \
        -project "$XCODE_PROJECT" \
        -scheme "$IOS_TEST_SCHEME" \
        -configuration Debug \
        -destination "$IOS_TEST_DESTINATION" \
        -derivedDataPath "$output_root/derived-data" \
        -clonedSourcePackagesDirPath "$VERIFICATION_ROOT/source-packages" \
        -disableAutomaticPackageResolution \
        -skipPackageUpdates \
        -only-testing:"$IOS_TEST_TARGET" \
        MEDCUE_SIMULATOR_UNIT_TEST_BUILD=YES \
        test
    assert_verification_tree_safe
}

run_ios_ui_tests() {
    local output_root="$VERIFICATION_ROOT/ios-ui-tests"

    prepare_verification_directory "$output_root/derived-data" "iOS UI-test derived data"
    xcodebuild \
        -project "$XCODE_PROJECT" \
        -scheme "$IOS_TEST_SCHEME" \
        -configuration Debug \
        -destination "$IOS_TEST_DESTINATION" \
        -derivedDataPath "$output_root/derived-data" \
        -clonedSourcePackagesDirPath "$VERIFICATION_ROOT/source-packages" \
        -disableAutomaticPackageResolution \
        -skipPackageUpdates \
        -only-testing:"$IOS_UI_TEST_TARGET" \
        MEDCUE_SIMULATOR_UNIT_TEST_BUILD=YES \
        test
    assert_verification_tree_safe
}

verify_ios_unit_test_artifacts() {
    local products_dir="$VERIFICATION_ROOT/ios-unit-tests/derived-data/Build/Products/Debug-iphonesimulator"
    local app_bundle="$products_dir/MedicationAdherenceApp.app"
    local test_bundle="$app_bundle/PlugIns/MedicationAdherenceAppTests.xctest"
    local secrets_plist="$app_bundle/AISecrets.plist"
    local test_secrets_plist="$test_bundle/AISecrets.plist"

    assert_verification_directory "$app_bundle" "iOS unit-test host app"
    assert_verification_directory "$test_bundle" "iOS unit-test bundle"
    assert_verification_tree_safe
    assert_symlinks_contained "$app_bundle" "iOS unit-test host app"
    assert_symlinks_contained "$test_bundle" "iOS unit-test bundle"
    [[ ! -e "$secrets_plist" && ! -L "$secrets_plist" ]] || fail "sensitive plist found in iOS unit-test host: $secrets_plist"
    [[ ! -e "$test_secrets_plist" && ! -L "$test_secrets_plist" ]] || fail "sensitive plist found in iOS unit-test bundle: $test_secrets_plist"
}

assert_no_sensitive_artifacts() {
    local bundle_root="$1"
    local label="$2"
    local match
    assert_verification_directory "$bundle_root" "$label"
    assert_verification_tree_safe
    assert_symlinks_contained "$bundle_root" "$label"
    match="$(find -P "$bundle_root" \( -iname 'AISecrets.plist' -o -iname '.env.local' -o -iname '*.gguf' -o -iname '*.sqlite' -o -iname '*.sqlite-*' -o -iname '*.sqlite3' -o -iname '*.sqlite3-*' -o -iname '*.store' -o -iname '*.store-*' \) -print -quit)"
    [[ -z "$match" ]] || fail "$label contains a forbidden secret, model, or user database artifact"
}

verify_main_app_release_artifacts() {
    local app_bundle="$VERIFICATION_ROOT/main-app-release/products/Release-iphoneos/MedicationAdherenceApp.app"
    local secrets_plist="$app_bundle/AISecrets.plist"
    local watch_app="$app_bundle/Watch/MedicationAdherenceWatchApp.app"
    local watch_widget="$watch_app/PlugIns/MedicationAdherenceWatchWidget.appex"

    assert_verification_directory "$app_bundle" "Main App Release product"
    [[ ! -e "$secrets_plist" && ! -L "$secrets_plist" ]] || fail "sensitive plist found in Main App Release product: $secrets_plist"
    assert_verification_directory "$watch_app" "embedded Watch App"
    assert_verification_directory "$watch_widget" "embedded Watch Widget"
    [[ -f "$app_bundle/PrivacyInfo.xcprivacy" && ! -L "$app_bundle/PrivacyInfo.xcprivacy" ]] || fail "Main App privacy manifest missing from Release product"
    [[ -f "$watch_app/PrivacyInfo.xcprivacy" && ! -L "$watch_app/PrivacyInfo.xcprivacy" ]] || fail "Watch App privacy manifest missing from Release product"
    [[ -f "$watch_widget/PrivacyInfo.xcprivacy" && ! -L "$watch_widget/PrivacyInfo.xcprivacy" ]] || fail "Watch Widget privacy manifest missing from Release product"
    assert_no_sensitive_artifacts "$app_bundle" "Main App Release product"
}

main() {
    parse_arguments "$@"
    cd "$ROOT_DIR"

    require_command git
    require_command mktemp
    require_command plutil
    require_command python3
    require_command realpath
    require_command swift
    require_command unzip
    require_command xcodebuild
    require_file "$PROJECT_FILE"
    require_file "$SWIFT_CORE_DIR/Package.swift"
    require_file "$PREFLIGHT_SCRIPT"
    require_file "$SOURCE_PACKAGE_BUILDER"
    require_file "$SOURCE_PACKAGE_TESTS"
    require_file "$SOURCE_PACKAGE_VERIFIER"
    require_file "$SOURCE_SIZE_SCRIPT"

    run_step "Git diff check" verify_git_diff
    run_step "Exact source-package gate" run_source_package_gate
    run_step "Xcode project plist lint" plutil -lint "$PROJECT_FILE"
    run_step "Swift source size limit" bash "$SOURCE_SIZE_SCRIPT"
    run_step "iOS preflight" bash "$PREFLIGHT_SCRIPT"

    if [[ "$CHECKS_ONLY" == 1 ]]; then
        printf '\n[PASS] Non-build checks completed; Swift tests and Xcode builds were intentionally skipped.\n'
        return
    fi

    prepare_verification_root

    run_step "Swift Core tests" run_swift_core_tests
    run_step "iOS hosted unit tests" run_ios_unit_tests
    run_step "iOS unit-test artifact assertions" verify_ios_unit_test_artifacts
    run_step "iOS UI tests" run_ios_ui_tests
    run_step "Main App unsigned Release" run_xcode_build "$MAIN_APP_TARGET" Release main-app-release
    run_step "Main App Release artifact assertions" verify_main_app_release_artifacts
    run_step "Watch Simulator Debug" run_xcode_build "$WATCH_APP_TARGET" Debug watch-simulator-debug "$WATCH_SIMULATOR_SDK"
    run_step "watchOS device SDK Release" run_xcode_build "$WATCH_APP_TARGET" Release watch-device-release "$WATCH_DEVICE_SDK"

    printf '\n[PASS] Route A native verification completed.\n'
}

main "$@"

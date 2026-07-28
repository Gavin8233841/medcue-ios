#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj"
XCODE_PROJECT="$ROOT_DIR/ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj"
SWIFT_CORE_DIR="$ROOT_DIR/swift-core"
PREFLIGHT_SCRIPT="$ROOT_DIR/tools/ios-preflight-check.sh"
SOURCE_SIZE_SCRIPT="$ROOT_DIR/tools/swift-source-size-check.sh"

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
    while [[ ! -e "$existing_ancestor" ]]; do
        existing_ancestor="$(dirname "$existing_ancestor")"
    done
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
    mkdir -p \
        "$VERIFICATION_ROOT/tmp" \
        "$VERIFICATION_ROOT/module-cache/clang" \
        "$VERIFICATION_ROOT/module-cache/swift" \
        "$VERIFICATION_ROOT/swift-core/cache" \
        "$VERIFICATION_ROOT/swift-core/scratch" \
        "$VERIFICATION_ROOT/source-packages"

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

    if [[ -n "$sdk" ]]; then
        xcodebuild_arguments+=(-sdk "$sdk")
    fi

    mkdir -p \
        "$output_root/products" \
        "$output_root/objects" \
        "$output_root/symbols"

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
}

run_ios_unit_tests() {
    local output_root="$VERIFICATION_ROOT/ios-unit-tests"

    mkdir -p "$output_root/derived-data"
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
}

run_ios_ui_tests() {
    local output_root="$VERIFICATION_ROOT/ios-ui-tests"

    mkdir -p "$output_root/derived-data"
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
}

verify_ios_unit_test_artifacts() {
    local products_dir="$VERIFICATION_ROOT/ios-unit-tests/derived-data/Build/Products/Debug-iphonesimulator"
    local app_bundle="$products_dir/MedicationAdherenceApp.app"
    local test_bundle="$app_bundle/PlugIns/MedicationAdherenceAppTests.xctest"
    local secrets_plist="$app_bundle/AISecrets.plist"
    local test_secrets_plist="$test_bundle/AISecrets.plist"

    [[ -d "$app_bundle" ]] || fail "iOS unit-test host app not found: $app_bundle"
    [[ -d "$test_bundle" ]] || fail "iOS unit-test bundle not found: $test_bundle"
    [[ ! -e "$secrets_plist" && ! -L "$secrets_plist" ]] || fail "sensitive plist found in iOS unit-test host: $secrets_plist"
    [[ ! -e "$test_secrets_plist" && ! -L "$test_secrets_plist" ]] || fail "sensitive plist found in iOS unit-test bundle: $test_secrets_plist"
}

assert_no_sensitive_artifacts() {
    local bundle_root="$1"
    local label="$2"
    local match
    match="$(find "$bundle_root" -type f \( -name 'AISecrets.plist' -o -name '.env.local' -o -name '*.gguf' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print -quit)"
    [[ -z "$match" ]] || fail "$label contains a forbidden secret, model, or user database artifact"
}

verify_main_app_release_artifacts() {
    local app_bundle="$VERIFICATION_ROOT/main-app-release/products/Release-iphoneos/MedicationAdherenceApp.app"
    local secrets_plist="$app_bundle/AISecrets.plist"
    local watch_app="$app_bundle/Watch/MedicationAdherenceWatchApp.app"
    local watch_widget="$watch_app/PlugIns/MedicationAdherenceWatchWidget.appex"

    [[ -d "$app_bundle" ]] || fail "Main App Release product not found: $app_bundle"
    [[ ! -e "$secrets_plist" && ! -L "$secrets_plist" ]] || fail "sensitive plist found in Main App Release product: $secrets_plist"
    [[ -d "$watch_app" ]] || fail "embedded Watch App not found: $watch_app"
    [[ -d "$watch_widget" ]] || fail "embedded Watch Widget not found: $watch_widget"
    [[ -f "$app_bundle/PrivacyInfo.xcprivacy" ]] || fail "Main App privacy manifest missing from Release product"
    [[ -f "$watch_app/PrivacyInfo.xcprivacy" ]] || fail "Watch App privacy manifest missing from Release product"
    [[ -f "$watch_widget/PrivacyInfo.xcprivacy" ]] || fail "Watch Widget privacy manifest missing from Release product"
    assert_no_sensitive_artifacts "$app_bundle" "Main App Release product"
}

main() {
    parse_arguments "$@"
    cd "$ROOT_DIR"

    require_command git
    require_command plutil
    require_command realpath
    require_command rg
    require_command swift
    require_command xcodebuild
    require_file "$PROJECT_FILE"
    require_file "$SWIFT_CORE_DIR/Package.swift"
    require_file "$PREFLIGHT_SCRIPT"
    require_file "$SOURCE_SIZE_SCRIPT"

    run_step "Git diff check" git diff --check
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

#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/ios-app/MedicationAdherenceApp"
PROJECT_FILE="$PROJECT_DIR/MedicationAdherenceApp.xcodeproj/project.pbxproj"
SHARED_SCHEME="$PROJECT_DIR/MedicationAdherenceApp.xcodeproj/xcshareddata/xcschemes/MedicationAdherenceApp.xcscheme"
APP_DIR="$PROJECT_DIR/MedicationAdherenceApp"
IOS_TEST_SOURCE="$PROJECT_DIR/MedicationAdherenceAppTests/MedicationAdherenceAppTests.swift"
APP_INFO="$APP_DIR/Info.plist"
APP_ENTITLEMENTS="$APP_DIR/MedicationAdherenceApp.entitlements"
AI_SECRETS="$APP_DIR/AISecrets.plist"
LOCAL_MODEL_STORE="$APP_DIR/Services/LocalMedicalModelStore.swift"
LOCAL_MODEL_CLIENT="$APP_DIR/Services/LocalMedicalAIClient.swift"
LOCAL_MODEL_RUNTIME="$APP_DIR/Services/LocalMedicalModelRuntime.swift"
PRIVACY_MANIFEST="$APP_DIR/WatchSupport/PrivacyInfo.xcprivacy"
PRIVACY_AUDIT="$ROOT_DIR/docs/24-privacy-data-flow-audit-20260727.md"
LLAMA_FRAMEWORK="$PROJECT_DIR/Frameworks/llama.xcframework"
LLAMA_PACKAGE_MANIFEST="$ROOT_DIR/Packages/LlamaFramework/Package.swift"
LLAMA_INSTALL_SCRIPT="$ROOT_DIR/tools/install-llama-xcframework.sh"
LOCAL_MODEL_SMOKE_SCRIPT="$ROOT_DIR/tools/run-local-model-smoke.sh"
LIVE_ACTIVITY_DIR="$PROJECT_DIR/MedicationReminderLiveActivityExtension"
LIVE_ACTIVITY_INFO="$LIVE_ACTIVITY_DIR/Info.plist"

failures=0
warnings=0

section() {
    printf '\n== %s ==\n' "$1"
}

pass() {
    printf '[PASS] %s\n' "$1"
}

warn() {
    warnings=$((warnings + 1))
    printf '[WARN] %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf '[FAIL] %s\n' "$1"
}

require_file() {
    local path="$1"
    local label="$2"
    if [[ -f "$path" ]]; then
        pass "$label exists"
    else
        fail "$label missing: $path"
    fi
}

plist_value() {
    local path="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$path" 2>/dev/null || true
}

plist_nested_value() {
    local path="$1"
    local key_path="$2"
    /usr/libexec/PlistBuddy -c "Print :$key_path" "$path" 2>/dev/null || true
}

require_plist_value() {
    local path="$1"
    local key="$2"
    local expected="$3"
    local label="$4"
    local value
    value="$(plist_value "$path" "$key")"
    if [[ "$value" == "$expected" ]]; then
        pass "$label = $expected"
    else
        fail "$label expected '$expected', got '${value:-<missing>}'"
    fi
}

require_plist_nonempty() {
    local path="$1"
    local key="$2"
    local label="$3"
    local value
    value="$(plist_value "$path" "$key")"
    if [[ -n "$value" ]]; then
        pass "$label present"
    else
        fail "$label missing"
    fi
}

require_text() {
    local path="$1"
    local needle="$2"
    local label="$3"
    if grep -Fq -- "$needle" "$path"; then
        pass "$label"
    else
        fail "$label missing"
    fi
}

project_object_block_by_id() {
	local object_id="$1"
	awk -v object_id="$object_id" '
		$1 == object_id && $0 ~ / = \{$/ { in_block = 1 }
		in_block { print }
		in_block && $0 ~ /^\t\t};$/ { exit }
	' "$PROJECT_FILE"
}

section "Paths"
require_file "$PROJECT_FILE" "Xcode project"
require_file "$SHARED_SCHEME" "Shared MedicationAdherenceApp scheme"
require_file "$IOS_TEST_SOURCE" "iOS unit test source"
require_file "$APP_INFO" "Main app Info.plist"
require_file "$APP_ENTITLEMENTS" "Main app entitlements"
require_file "$LIVE_ACTIVITY_INFO" "Live Activity extension Info.plist"
require_file "$PRIVACY_MANIFEST" "Privacy manifest"
require_file "$PRIVACY_AUDIT" "Privacy data-flow audit"

section "Main App Identity"
if [[ -f "$APP_INFO" ]]; then
    require_plist_value "$APP_INFO" "CFBundleDisplayName" "用药跟踪" "Display name"
    require_plist_value "$APP_INFO" "CFBundleName" "MedCue" "Bundle name"
    require_plist_value "$APP_INFO" "NSSupportsLiveActivities" "true" "Live Activities support"
    require_plist_nonempty "$APP_INFO" "NSAlarmKitUsageDescription" "AlarmKit usage description"
    require_plist_nonempty "$APP_INFO" "NSCameraUsageDescription" "Camera usage description"
    require_plist_nonempty "$APP_INFO" "NSHealthShareUsageDescription" "HealthKit usage description"
    require_plist_nonempty "$APP_INFO" "NSLocationWhenInUseUsageDescription" "Location usage description"
    url_scheme="$(plist_nested_value "$APP_INFO" "CFBundleURLTypes:0:CFBundleURLSchemes:0")"
    if [[ "$url_scheme" == "medicationadherence" ]]; then
        pass "Live Activity callback URL scheme = medicationadherence"
    else
        fail "Live Activity callback URL scheme expected medicationadherence, got '${url_scheme:-<missing>}'"
    fi
fi

section "Entitlements"
if [[ -f "$APP_ENTITLEMENTS" ]]; then
    healthkit="$(plist_value "$APP_ENTITLEMENTS" "com.apple.developer.healthkit")"
    if [[ "$healthkit" == "true" ]]; then
        pass "HealthKit entitlement enabled"
    else
        fail "HealthKit entitlement missing or disabled"
    fi
    app_group="$(plist_nested_value "$APP_ENTITLEMENTS" "com.apple.security.application-groups:0")"
    if [[ "$app_group" == "group.com.gwyy.appcontest2026.medicationadherence.watch" ]]; then
        pass "App Group entitlement present for Watch snapshot storage"
    else
        warn "App Group entitlement not found at expected path; Watch features may need provisioning review"
    fi
fi

section "Medical AI Secret Boundary"
if [[ -f "$AI_SECRETS" ]]; then
	pass "Debug-only local AI configuration exists (contents intentionally not inspected)"
else
	warn "Debug-only local AI configuration is absent; ordinary Debug builds fail by design, while explicitly marked simulator unit-test hosts exclude it"
fi
if git ls-files | grep -Eq '(^|/)(AISecrets\.plist|\.env\.local)$|\.gguf$'; then
	fail "Git tracks a forbidden secret or GGUF artifact"
else
	pass "Git does not track AISecrets.plist, .env.local, or GGUF artifacts"
fi

section "Privacy Manifest"
if [[ -f "$PRIVACY_MANIFEST" ]]; then
	if plutil -lint "$PRIVACY_MANIFEST" >/dev/null; then
		pass "Privacy manifest plist lint"
	else
		fail "Privacy manifest plist lint failed"
	fi
	require_text "$PRIVACY_MANIFEST" "NSPrivacyAccessedAPICategoryUserDefaults" "Privacy manifest declares UserDefaults required-reason API"
	require_text "$PRIVACY_MANIFEST" "1C8F.1" "Privacy manifest includes app preference reason"
	require_text "$PRIVACY_MANIFEST" "CA92.1" "Privacy manifest includes App Group preference reason"
fi

section "Local Medical Model"
require_file "$LOCAL_MODEL_STORE" "Local model download store"
require_file "$LOCAL_MODEL_CLIENT" "Local model AI client"
require_file "$LOCAL_MODEL_RUNTIME" "Local model runtime adapter"
require_file "$LLAMA_PACKAGE_MANIFEST" "Local llama Swift package manifest"
require_file "$LLAMA_INSTALL_SCRIPT" "llama.xcframework install script"
require_file "$LOCAL_MODEL_SMOKE_SCRIPT" "Local model smoke script"
if [[ -d "$LLAMA_FRAMEWORK" ]]; then
    pass "llama.xcframework installed"
else
    warn "llama.xcframework missing; offline model responses stay disabled until installed"
fi
if [[ -f "$LOCAL_MODEL_STORE" ]]; then
    require_text "$LOCAL_MODEL_STORE" "MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf" "MiniCPM4 GGUF filename registered"
    require_text "$LOCAL_MODEL_STORE" "LocalAIModelManager" "Local model manager validates the installed model"
    require_text "$LOCAL_MODEL_STORE" "MiniCPM4-0.5B" "Local model manager uses the dedicated MiniCPM4 Application Support directory"
    require_text "$LOCAL_MODEL_STORE" "minimumByteCount: 200 * 1024 * 1024" "Local model manager validates minimum GGUF size"
    require_text "$LOCAL_MODEL_STORE" "maximumByteCount: 350 * 1024 * 1024" "Local model manager validates maximum GGUF size"
    require_text "$LOCAL_MODEL_STORE" "BackgroundAssets" "Background Assets download path wired"
fi
if [[ -f "$LOCAL_MODEL_RUNTIME" ]]; then
    require_text "$LOCAL_MODEL_RUNTIME" "#if canImport(llama)" "llama runtime is conditionally wired"
fi
if [[ -f "$LLAMA_PACKAGE_MANIFEST" ]]; then
    require_text "$LLAMA_PACKAGE_MANIFEST" "LlamaFramework" "Local llama package product registered"
    require_text "$LLAMA_PACKAGE_MANIFEST" "../../ios-app/MedicationAdherenceApp/Frameworks/llama.xcframework" "Local llama package points at app Frameworks directory"
fi
if [[ -f "$PROJECT_FILE" ]]; then
    require_text "$PROJECT_FILE" "LlamaFramework in Frameworks" "Main app links local llama package product"
    require_text "$PROJECT_FILE" "../../Packages/LlamaFramework" "Main app references local llama package"
fi
require_text "$APP_DIR/MedicationAdherenceApp.swift" "--local-medical-model-smoke-test" "Local model smoke test launch argument wired"
if [[ -f "$LOCAL_MODEL_SMOKE_SCRIPT" ]]; then
    require_text "$LOCAL_MODEL_SMOKE_SCRIPT" "LOCAL_MODEL_GGUF" "Local model smoke script can stage GGUF into simulator data container"
    require_text "$LOCAL_MODEL_SMOKE_SCRIPT" "Models/MiniCPM4-0.5B" "Local model smoke script stages GGUF into the product Application Support path"
fi
require_text "$ROOT_DIR/.gitignore" "*.gguf" "GGUF model files are ignored by Git"
require_text "$ROOT_DIR/.gitignore" "/Models/" "Root-level model cache directory is ignored by Git"
require_text "$ROOT_DIR/.gitignore" "/DerivedModels/" "Derived model cache directory is ignored by Git"
require_text "$ROOT_DIR/.gitignore" "/ApplicationSupportModels/" "Application Support model staging directory is ignored by Git"

section "Project Wiring"
if [[ -f "$SHARED_SCHEME" ]]; then
    require_text "$SHARED_SCHEME" 'BlueprintIdentifier = "A50000000000000000000001"' "Shared scheme references the main app target"
    require_text "$SHARED_SCHEME" 'BlueprintIdentifier = "A89A5AD0300B790100BD46AA"' "Shared scheme includes the iOS unit test target"
fi
if [[ -f "$PROJECT_FILE" ]]; then
    require_text "$PROJECT_FILE" "Copy Local AI Secrets" "Copy Local AI Secrets build phase wired"
	secrets_phase_block="$(project_object_block_by_id "A80000000000000000000003")"
	if [[ -z "$secrets_phase_block" ]]; then
		fail "Unable to inspect local AI configuration build phase"
	elif [[ "$secrets_phase_block" == *'if [ \"${CONFIGURATION}\" != \"Debug\" ]; then\n'*'exit 0\nfi\n\nif [ \"${MEDCUE_SIMULATOR_UNIT_TEST_BUILD:-NO}\" = \"YES\" ]; then\n'*'if [ \"${PLATFORM_NAME}\" != \"iphonesimulator\" ]; then\n'*'MEDCUE_SIMULATOR_UNIT_TEST_BUILD may only be used for iOS Simulator unit tests.'*'Local AI configuration excluded from simulator unit-test host.'*'exit 0\nfi\n\nSECRETS_FILE='*'if [ ! -f \"${SECRETS_FILE}\" ]; then\n'*'cp \"${SECRETS_FILE}\" \"${DESTINATION}\"'* ]]; then
		pass "Local AI configuration is excluded only for explicitly marked simulator unit-test hosts and otherwise copied after the Debug guard"
	else
		fail "Local AI configuration build phase does not enforce the Debug and simulator unit-test boundaries"
	fi
	if [[ "$secrets_phase_block" == *'echo \"${'* ]] ||
		[[ "$secrets_phase_block" == *'cat \"${SECRETS_FILE}\"'* ]] ||
		[[ "$secrets_phase_block" == *'plutil'* ]] ||
		[[ "$secrets_phase_block" == *'PlistBuddy'* ]]; then
		fail "Local AI configuration build phase may expose or parse sensitive values"
	else
		pass "Local AI configuration build phase does not print or parse sensitive values"
	fi
	project_secret_reference_count="$(grep -Fo 'AISecrets.plist' "$PROJECT_FILE" | wc -l | tr -d '[:space:]')"
	phase_secret_reference_count="$(grep -Fo 'AISecrets.plist' <<< "$secrets_phase_block" | wc -l | tr -d '[:space:]')"
	if [[ "$phase_secret_reference_count" != "0" ]] &&
		[[ "$project_secret_reference_count" == "$phase_secret_reference_count" ]]; then
		pass "Local AI configuration filename is confined to the guarded build phase"
	else
		fail "Local AI configuration may be referenced outside the guarded build phase"
	fi
    require_text "$PROJECT_FILE" "MedicationReminderLiveActivityExtension.appex in Embed App Extensions" "Live Activity extension embedded in main app"
    require_text "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = com.gwyy.appcontest2026.medicationadherence;" "Main app bundle identifier configured"
    require_text "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = com.gwyy.appcontest2026.medicationadherence.MedicationReminderLiveActivityExtension;" "Live Activity extension bundle identifier configured"
    require_text "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = com.gwyy.appcontest2026.MedicationAdherenceAppTests;" "iOS unit test bundle identifier configured"
    require_text "$PROJECT_FILE" "TestTargetID = A50000000000000000000001;" "iOS unit test target associated with the main app"
	main_target_block="$(project_object_block_by_id "A50000000000000000000001")"
	if [[ -z "$main_target_block" ]]; then
		fail "Unable to inspect main app target wiring"
	elif grep -Fq "C80000000000000000000004 /* Embed Watch Content */" <<< "$main_target_block" &&
		grep -Fq "C70000000000000000000001 /* PBXTargetDependency */" <<< "$main_target_block"; then
		pass "Watch content embed phase and target dependency wired into main app"
	else
		fail "Watch content embed phase or target dependency missing from main app target"
	fi
	if grep -Fq "MedicationAdherenceWatchApp.app in Embed Watch Content" "$PROJECT_FILE"; then
		pass "Watch app product registered in Embed Watch Content phase"
	fi
fi

section "Current UI Route Expectations"
if grep -Fq "今日 / 药品 / AI 助手 / 记录 / 个人" "$ROOT_DIR/docs/13-iphone-signing-and-live-activity-test.md"; then
    pass "Real-device checklist matches current five-tab structure"
else
    fail "Real-device checklist does not mention current five-tab structure"
fi
if grep -Fq "风险复核已并入" "$ROOT_DIR/docs/13-iphone-signing-and-live-activity-test.md"; then
    pass "Real-device checklist notes risk review is under Medications"
else
    fail "Real-device checklist may still imply a standalone risk tab"
fi

section "Summary"
if (( failures == 0 )); then
    printf 'Preflight passed with %d warning(s).\n' "$warnings"
    exit 0
else
    printf 'Preflight failed with %d failure(s) and %d warning(s).\n' "$failures" "$warnings"
    exit 1
fi

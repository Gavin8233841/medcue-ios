#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_DIR="$ROOT_DIR/ios-app/MedicationAdherenceApp"
PROJECT_PATH="$PROJECT_DIR/MedicationAdherenceApp.xcodeproj"
SCHEME="${SCHEME:-MedicationAdherenceApp}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
BUNDLE_ID="${BUNDLE_ID:-com.gwyy.appcontest2026.medicationadherence}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.codex-local/local-model-smoke-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/MedicationAdherenceApp.app"
LOCAL_MODEL_GGUF="${LOCAL_MODEL_GGUF:-}"
LOCAL_MODEL_SMOKE_REPEAT_COUNT="${LOCAL_MODEL_SMOKE_REPEAT_COUNT:-1}"
EXPECTED_MODEL_NAME="MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf"
MIN_MODEL_BYTES=$((200 * 1024 * 1024))
MAX_MODEL_BYTES=$((350 * 1024 * 1024))

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "DEVELOPER_DIR does not exist: $DEVELOPER_DIR" >&2
  exit 2
fi

if [[ -n "$LOCAL_MODEL_GGUF" ]]; then
  if [[ ! -f "$LOCAL_MODEL_GGUF" ]]; then
    echo "LOCAL_MODEL_GGUF does not exist: $LOCAL_MODEL_GGUF" >&2
    exit 2
  fi
  if [[ "$(basename "$LOCAL_MODEL_GGUF")" != "$EXPECTED_MODEL_NAME" ]]; then
    echo "LOCAL_MODEL_GGUF must point to $EXPECTED_MODEL_NAME: $LOCAL_MODEL_GGUF" >&2
    exit 2
  fi
  MODEL_BYTES="$(stat -f '%z' "$LOCAL_MODEL_GGUF")"
  if (( MODEL_BYTES < MIN_MODEL_BYTES || MODEL_BYTES > MAX_MODEL_BYTES )); then
    echo "LOCAL_MODEL_GGUF size is outside the expected 200MB-350MB range: ${MODEL_BYTES} bytes" >&2
    exit 2
  fi
fi

echo "Building $SCHEME for $SIMULATOR_NAME..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

SIMULATOR_ID="$(xcrun simctl list devices available | sed -n "s/.*$SIMULATOR_NAME (\([0-9A-F-]*\)).*/\1/p" | head -n 1)"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Simulator not found: $SIMULATOR_NAME" >&2
  exit 1
fi

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

if [[ -n "$LOCAL_MODEL_GGUF" ]]; then
  DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_ID" "$BUNDLE_ID" data)"
  MODEL_DIRECTORY="$DATA_CONTAINER/Library/Application Support/Models/MiniCPM4-0.5B"
  MODEL_DESTINATION="$MODEL_DIRECTORY/$EXPECTED_MODEL_NAME"

  mkdir -p "$MODEL_DIRECTORY"
  if [[ ! -f "$MODEL_DESTINATION" ]]; then
    cp "$LOCAL_MODEL_GGUF" "$MODEL_DESTINATION"
  fi
  echo "Prepared local model for simulator: $MODEL_DESTINATION ($(stat -f '%z' "$MODEL_DESTINATION") bytes)"
fi

set +e
LAUNCH_OUTPUT="$(
  SIMCTL_CHILD_LOCAL_MODEL_SMOKE_REPEAT_COUNT="$LOCAL_MODEL_SMOKE_REPEAT_COUNT" \
    xcrun simctl launch \
    --terminate-running-process \
    --console-pty \
    "$SIMULATOR_ID" \
    "$BUNDLE_ID" \
    --local-medical-model-smoke-test 2>&1
)"
LAUNCH_STATUS=$?
set -e

printf '%s\n' "$LAUNCH_OUTPUT"
if grep -Fq "[LocalMedicalModel-Smoke] success" <<< "$LAUNCH_OUTPUT"; then
  exit 0
fi
if grep -Fq "[LocalMedicalModel-Smoke] failure" <<< "$LAUNCH_OUTPUT"; then
  exit 1
fi
if (( LAUNCH_STATUS != 0 )); then
  exit "$LAUNCH_STATUS"
fi

echo "No LocalMedicalModel smoke result was captured from app console output." >&2
exit 1

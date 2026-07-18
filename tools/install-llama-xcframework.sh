#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_TAG="${LLAMA_CPP_RELEASE_TAG:-b9596}"
ASSET_NAME="llama-${RELEASE_TAG}-xcframework.zip"
DOWNLOAD_URL="https://github.com/ggml-org/llama.cpp/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
LOCAL_CACHE_DIR="${WORKSPACE_ROOT}/.codex-local"
ZIP_PATH="${LLAMA_XCFRAMEWORK_ZIP:-${LOCAL_CACHE_DIR}/${ASSET_NAME}}"
SOURCE_FRAMEWORK="${LLAMA_XCFRAMEWORK_DIR:-}"
FRAMEWORK_DESTINATION="${WORKSPACE_ROOT}/ios-app/MedicationAdherenceApp/Frameworks/llama.xcframework"

mkdir -p "$LOCAL_CACHE_DIR"

if [[ -n "$SOURCE_FRAMEWORK" ]]; then
  if [[ ! -d "$SOURCE_FRAMEWORK" ]]; then
    echo "LLAMA_XCFRAMEWORK_DIR does not exist: $SOURCE_FRAMEWORK" >&2
    exit 2
  fi
  if [[ "$(basename "$SOURCE_FRAMEWORK")" != "llama.xcframework" ]]; then
    echo "LLAMA_XCFRAMEWORK_DIR must point to llama.xcframework: $SOURCE_FRAMEWORK" >&2
    exit 2
  fi
  if [[ -e "$FRAMEWORK_DESTINATION" ]]; then
    echo "Refusing to overwrite existing framework: $FRAMEWORK_DESTINATION" >&2
    exit 2
  fi
  mkdir -p "$(dirname "$FRAMEWORK_DESTINATION")"
  cp -R "$SOURCE_FRAMEWORK" "$FRAMEWORK_DESTINATION"
  echo "$FRAMEWORK_DESTINATION"
  exit 0
fi

if [[ -n "${LLAMA_XCFRAMEWORK_ZIP:-}" && ! -f "$ZIP_PATH" ]]; then
  echo "LLAMA_XCFRAMEWORK_ZIP does not exist: $ZIP_PATH" >&2
  exit 2
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Downloading ${ASSET_NAME}..."
  curl -L --fail --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 1800 \
    -o "$ZIP_PATH" \
    "$DOWNLOAD_URL"
fi

if [[ -e "$FRAMEWORK_DESTINATION" ]]; then
  echo "Refusing to overwrite existing framework: $FRAMEWORK_DESTINATION" >&2
  exit 2
fi

UNPACK_DIR="${LOCAL_CACHE_DIR}/llama-xcframework-unpack-$(date +%Y%m%d%H%M%S)"
mkdir -p "$UNPACK_DIR"
ditto -x -k "$ZIP_PATH" "$UNPACK_DIR"

FOUND_FRAMEWORK="$(find "$UNPACK_DIR" -name 'llama.xcframework' -type d -maxdepth 5 -print -quit)"
if [[ -z "$FOUND_FRAMEWORK" ]]; then
  echo "No llama.xcframework found after unpacking: $ZIP_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$FRAMEWORK_DESTINATION")"
cp -R "$FOUND_FRAMEWORK" "$FRAMEWORK_DESTINATION"

echo "$FRAMEWORK_DESTINATION"

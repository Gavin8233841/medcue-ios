#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${LLAMA_CPP_DIR:-}" ]]; then
  echo "Set LLAMA_CPP_DIR to a local ggml-org/llama.cpp checkout." >&2
  exit 2
fi

if [[ ! -d "$LLAMA_CPP_DIR" ]]; then
  echo "LLAMA_CPP_DIR does not exist: $LLAMA_CPP_DIR" >&2
  exit 2
fi

if [[ ! -x "$LLAMA_CPP_DIR/build-xcframework.sh" ]]; then
  echo "Missing executable build-xcframework.sh under: $LLAMA_CPP_DIR" >&2
  exit 2
fi

(
  cd "$LLAMA_CPP_DIR"
  ./build-xcframework.sh
)

framework_path="$LLAMA_CPP_DIR/build-apple/llama.xcframework"
if [[ ! -d "$framework_path" ]]; then
  echo "Build finished, but llama.xcframework was not found at: $framework_path" >&2
  exit 1
fi

echo "$framework_path"

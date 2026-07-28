#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_LINES="${SWIFT_SOURCE_MAX_LINES:-2000}"

case "$MAX_LINES" in
    ''|*[!0-9]*)
        printf 'swift-source-size-check: SWIFT_SOURCE_MAX_LINES must be a positive integer\n' >&2
        exit 2
        ;;
esac
if ((MAX_LINES < 1)); then
    printf 'swift-source-size-check: SWIFT_SOURCE_MAX_LINES must be a positive integer\n' >&2
    exit 2
fi

failures=0
largest_lines=0
largest_file=""

while IFS= read -r relative_path; do
    line_count="$(wc -l < "$ROOT_DIR/$relative_path" | tr -d ' ')"
    if ((line_count > largest_lines)); then
        largest_lines="$line_count"
        largest_file="$relative_path"
    fi
    if ((line_count > MAX_LINES)); then
        printf '[FAIL] %s has %d lines (limit %d)\n' "$relative_path" "$line_count" "$MAX_LINES" >&2
        failures=$((failures + 1))
    fi
done < <(
    cd "$ROOT_DIR"
    rg --files ios-app/MedicationAdherenceApp swift-core \
        -g '*.swift' \
        -g '!**/.build/**' \
        -g '!**/.codex-build*/**' \
        -g '!**/.codex-deriveddata*/**' \
        | sort
)

if ((failures > 0)); then
    printf 'swift-source-size-check: %d file(s) exceed the %d-line limit\n' "$failures" "$MAX_LINES" >&2
    exit 1
fi

printf '[PASS] Swift source size limit %d lines; largest is %s (%d lines)\n' \
    "$MAX_LINES" "$largest_file" "$largest_lines"

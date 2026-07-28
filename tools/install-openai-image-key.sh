#!/usr/bin/env bash
set -euo pipefail

SERVICE="appcontest-openai-image"
ACCOUNT="openai-image-api"

printf 'This stores the OpenAI API key in macOS Keychain.\n'
printf 'Service: %s\n' "$SERVICE"
printf 'Account: %s\n' "$ACCOUNT"
printf 'Paste the full key when prompted. Input is hidden by macOS security.\n'

security add-generic-password \
  -a "$ACCOUNT" \
  -s "$SERVICE" \
  -U \
  -w

printf 'Stored OpenAI image API key in macOS Keychain.\n'

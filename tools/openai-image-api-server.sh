#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME:?HOME must be set}/.cache}"
BUNDLED_NODE="${CACHE_HOME}/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"

configure_proxy() {
  if [[ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}${ALL_PROXY:-}${https_proxy:-}${http_proxy:-}${all_proxy:-}" ]]; then
    export NODE_USE_ENV_PROXY=1
    return
  fi

  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v scutil >/dev/null 2>&1; then
    return
  fi

  local proxy_info https_enabled https_host https_port http_enabled http_host http_port proxy_url
  proxy_info="$(scutil --proxy 2>/dev/null || true)"

  https_enabled="$(printf '%s\n' "$proxy_info" | awk '/HTTPSEnable/ {print $3; exit}')"
  https_host="$(printf '%s\n' "$proxy_info" | awk '/HTTPSProxy/ {print $3; exit}')"
  https_port="$(printf '%s\n' "$proxy_info" | awk '/HTTPSPort/ {print $3; exit}')"

  if [[ "$https_enabled" == "1" && -n "$https_host" && -n "$https_port" ]]; then
    proxy_url="http://${https_host}:${https_port}"
  else
    http_enabled="$(printf '%s\n' "$proxy_info" | awk '/HTTPEnable/ {print $3; exit}')"
    http_host="$(printf '%s\n' "$proxy_info" | awk '/HTTPProxy/ {print $3; exit}')"
    http_port="$(printf '%s\n' "$proxy_info" | awk '/HTTPPort/ {print $3; exit}')"
    if [[ "$http_enabled" == "1" && -n "$http_host" && -n "$http_port" ]]; then
      proxy_url="http://${http_host}:${http_port}"
    else
      return
    fi
  fi

  export HTTPS_PROXY="$proxy_url"
  export HTTP_PROXY="$proxy_url"
  export https_proxy="$proxy_url"
  export http_proxy="$proxy_url"
  export NODE_USE_ENV_PROXY=1
}

if [[ -x "$BUNDLED_NODE" ]]; then
  NODE_BIN="$BUNDLED_NODE"
elif command -v node >/dev/null 2>&1; then
  NODE_BIN="$(command -v node)"
else
  printf 'Node.js was not found in the Codex runtime cache or PATH.\n' >&2
  exit 1
fi

configure_proxy

exec "$NODE_BIN" "$ROOT_DIR/tools/openai-image-api-server.mjs" "$@"

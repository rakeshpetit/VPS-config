#!/bin/bash
# Loads Agent Credentials into the process it launches (pi-web's session daemon,
# which starts the Pi sessions). Usage: pi-web-wrapper <command> [args...]
set -euo pipefail

read_secret() {
  local f="/run/secrets/$1"
  [ -r "$f" ] && tr -d '\r\n' < "$f"
}

OPENROUTER_API_KEY="$(read_secret openrouter_api_key || true)"
GH_TOKEN="$(read_secret github_token || true)"
export OPENROUTER_API_KEY GH_TOKEN

exec "$@"

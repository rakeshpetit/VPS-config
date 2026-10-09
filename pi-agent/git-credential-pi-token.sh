#!/bin/bash
# git credential helper: serves the GitHub token on demand for github.com only.
[ "${1:-}" = "get" ] || exit 0
host=""
while IFS='=' read -r k v; do
  [ "$k" = "host" ] && host="$v"
done
[ "$host" = "github.com" ] || exit 0
[ -r /run/secrets/github_token ] || exit 0
printf 'username=x-access-token\npassword=%s\n' "$(tr -d '\r\n' < /run/secrets/github_token)"

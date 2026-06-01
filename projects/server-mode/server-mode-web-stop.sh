#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/server-mode-common.sh"

if [[ ! -f "$WEB_PID_FILE" ]]; then
  printf '[server-mode-web] not running\n'
  exit 0
fi

web_pid="$(<"$WEB_PID_FILE")"
if [[ -n "$web_pid" ]] && kill -0 "$web_pid" 2>/dev/null; then
  kill "$web_pid"
  sleep 1
  if kill -0 "$web_pid" 2>/dev/null; then
    kill -9 "$web_pid" 2>/dev/null || true
  fi
  printf '[server-mode-web] stopped pid %s\n' "$web_pid"
else
  printf '[server-mode-web] stale pid file removed\n'
fi

rm -f "$WEB_PID_FILE"

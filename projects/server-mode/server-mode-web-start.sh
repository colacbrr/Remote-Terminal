#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/server-mode-common.sh"

mkdir -p "$STATE_DIR"

if [[ -f "$WEB_PID_FILE" ]]; then
  existing_pid="$(<"$WEB_PID_FILE")"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    printf '[server-mode-web] already running on http://%s:%s\n' "$WEB_HOST" "$WEB_PORT"
    exit 0
  fi
fi

nohup python3 "${script_dir}/server-mode-web.py" --host "$WEB_HOST" --port "$WEB_PORT" >>"$WEB_LOG_FILE" 2>&1 &
web_pid=$!
printf '%s\n' "$web_pid" >"$WEB_PID_FILE"
sleep 1

if kill -0 "$web_pid" 2>/dev/null; then
  printf '[server-mode-web] started on http://%s:%s (pid %s)\n' "$WEB_HOST" "$WEB_PORT" "$web_pid"
else
  printf '[server-mode-web] failed to start; see %s\n' "$WEB_LOG_FILE" >&2
  exit 1
fi

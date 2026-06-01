#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/server-mode-common.sh"

"${script_dir}/server-mode-web-start.sh"

if ! command -v tailscale >/dev/null 2>&1; then
  printf '[server-mode-publish] tailscale CLI not found\n' >&2
  exit 1
fi

tailscale serve --bg "$WEB_PORT"
printf '[server-mode-publish] published %s via Tailscale Serve\n' "$WEB_PORT"
printf '[server-mode-publish] URL: %s\n' "$(published_dashboard_url)"

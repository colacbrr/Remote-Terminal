#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/server-mode-common.sh"

if command -v tailscale >/dev/null 2>&1; then
  tailscale serve off
  printf '[server-mode-publish] Tailscale Serve disabled for this node\n'
fi

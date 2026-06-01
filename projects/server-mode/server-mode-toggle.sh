#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
enter_script="${script_dir}/enter-server-mode.sh"
exit_script="${script_dir}/exit-server-mode.sh"
state_file="/var/lib/remote-terminal-server-mode/state.env"

run_with_sudo_if_needed() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ -f "$state_file" ]]; then
  run_with_sudo_if_needed "$exit_script"
else
  run_with_sudo_if_needed "$enter_script" --require-ac
fi

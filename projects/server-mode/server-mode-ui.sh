#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf '[server-mode-ui] error: %s\n' "$*" >&2
  exit 1
}

have_whiptail() {
  command -v whiptail >/dev/null 2>&1
}

run_root_script() {
  local script_name

  script_name="$1"
  shift

  if [[ "${EUID}" -ne 0 ]]; then
    sudo "${script_dir}/${script_name}" "$@"
  else
    "${script_dir}/${script_name}" "$@"
  fi
}

enter_server_mode() {
  local selections require_ac=0 dry_run=0 skip_services=0 skip_logind=0 args=()

  selections="$(whiptail \
    --title "Enter Server Mode" \
    --checklist "Select the options to apply." 18 80 8 \
    "require-ac" "Fail if AC power is not detected" ON \
    "dry-run" "Preview actions without changing the system" OFF \
    "skip-services" "Do not enable or start tailscaled or SSH" OFF \
    "skip-logind" "Do not apply the temporary lid/idle override" OFF \
    3>&1 1>&2 2>&3)" || return 0

  selections="${selections//\"/}"

  case " ${selections} " in
    *" require-ac "*) require_ac=1 ;;
  esac
  case " ${selections} " in
    *" dry-run "*) dry_run=1 ;;
  esac
  case " ${selections} " in
    *" skip-services "*) skip_services=1 ;;
  esac
  case " ${selections} " in
    *" skip-logind "*) skip_logind=1 ;;
  esac

  [[ "$require_ac" -eq 1 ]] && args+=(--require-ac)
  [[ "$dry_run" -eq 1 ]] && args+=(--dry-run)
  [[ "$skip_services" -eq 1 ]] && args+=(--skip-services)
  [[ "$skip_logind" -eq 1 ]] && args+=(--skip-logind-policy)

  clear
  run_root_script enter-server-mode.sh "${args[@]}"
}

inspect_server_mode() {
  local choice

  choice="$(whiptail \
    --title "Inspect Server Mode" \
    --menu "Choose how to inspect the current saved state." 16 80 4 \
    "summary" "Run inspect-server-mode.sh and print the summary" \
    "dry-exit" "Preview exit actions with exit-server-mode.sh --dry-run" \
    "cancel" "Return without running anything" \
    3>&1 1>&2 2>&3)" || return 0

  clear
  case "$choice" in
    summary)
      run_root_script inspect-server-mode.sh
      ;;
    dry-exit)
      run_root_script exit-server-mode.sh --dry-run --keep-state
      ;;
    cancel)
      return 0
      ;;
  esac
}

exit_server_mode() {
  local choice keep_state=0 dry_run=0 args=()

  choice="$(whiptail \
    --title "Exit Server Mode" \
    --menu "Choose how to leave server mode." 18 80 6 \
    "close" "Restore state and stay running" \
    "restart" "Restore state and reboot the laptop" \
    "poweroff" "Restore state and power off the laptop" \
    "preview" "Preview the default close action" \
    "cancel" "Return without running anything" \
    3>&1 1>&2 2>&3)" || return 0

  case "$choice" in
    cancel)
      return 0
      ;;
    preview)
      dry_run=1
      keep_state=1
      ;;
    restart)
      args+=(--reboot)
      ;;
    poweroff)
      args+=(--poweroff)
      ;;
  esac

  if [[ "$dry_run" -eq 0 ]]; then
    if whiptail --yesno "Keep the saved state file after exit?" 10 70; then
      keep_state=1
    fi
  fi

  [[ "$dry_run" -eq 1 ]] && args+=(--dry-run)
  [[ "$keep_state" -eq 1 ]] && args+=(--keep-state)

  clear
  run_root_script exit-server-mode.sh "${args[@]}"
}

main() {
  local choice

  have_whiptail || die "whiptail is required for server-mode-ui.sh"

  while true; do
    choice="$(whiptail \
      --title "Server Mode" \
      --menu "Choose an action." 18 80 6 \
      "enter" "Configure options and enter server mode" \
      "inspect" "Inspect the saved state or preview exit" \
      "exit" "Leave server mode, reboot, or power off" \
      "quit" "Close the interface" \
      3>&1 1>&2 2>&3)" || exit 0

    case "$choice" in
      enter)
        enter_server_mode
        ;;
      inspect)
        inspect_server_mode
        ;;
      exit)
        exit_server_mode
        ;;
      quit)
        exit 0
        ;;
    esac

    printf '\n'
    read -r -p "Press Enter to return to the menu..."
  done
}

main "$@"

#!/usr/bin/env bash

set -euo pipefail

state_dir="/var/lib/remote-terminal-server-mode"
state_file="${state_dir}/state.env"
history_preview_limit=10

usage() {
  cat <<'EOF'
Usage: inspect-server-mode.sh [--help]

Inspect the saved server-mode state captured by enter-server-mode.sh without
restoring services or removing the state file.
EOF
}

die() {
  printf '[server-mode] error: %s\n' "$*" >&2
  exit 1
}

load_state() {
  [[ -f "$state_file" ]] || die "state file not found at ${state_file}; run enter-server-mode.sh first"
  # shellcheck disable=SC1090
  source "$state_file"
}

service_state() {
  local service state

  service="$1"
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    printf 'unknown\n'
  else
    printf '%s\n' "$state"
  fi
}

service_enabled_state() {
  local service state

  service="$1"
  state="$(systemctl is-enabled "$service" 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    printf 'unknown\n'
  else
    printf '%s\n' "$state"
  fi
}

seconds_since_recorded() {
  local recorded_epoch now_epoch

  if ! recorded_epoch="$(date -d "${RECORDED_AT}" +%s 2>/dev/null)"; then
    printf 'unknown\n'
    return 0
  fi

  now_epoch="$(date +%s)"
  printf '%s\n' "$((now_epoch - recorded_epoch))"
}

format_duration() {
  local total seconds minutes hours days

  total="$1"
  if [[ "$total" == "unknown" ]]; then
    printf 'unknown\n'
    return 0
  fi

  seconds="$((total % 60))"
  minutes="$(((total / 60) % 60))"
  hours="$(((total / 3600) % 24))"
  days="$((total / 86400))"

  if [[ "$days" -gt 0 ]]; then
    printf '%sd %02dh %02dm %02ds\n' "$days" "$hours" "$minutes" "$seconds"
  else
    printf '%02dh %02dm %02ds\n' "$hours" "$minutes" "$seconds"
  fi
}

current_history_line_count() {
  if [[ -n "${HISTORY_FILE:-}" && -f "${HISTORY_FILE}" ]]; then
    wc -l <"${HISTORY_FILE}" | tr -d ' '
  else
    printf 'unknown\n'
  fi
}

print_history_preview() {
  local start_line current_lines delta shell_name raw_preview

  if [[ -z "${HISTORY_FILE:-}" || "${HISTORY_FILE}" == "unknown" ]]; then
    printf '  New commands since enter: unavailable (history file unknown)\n'
    return 0
  fi

  if [[ ! -f "${HISTORY_FILE}" ]]; then
    printf '  New commands since enter: unavailable (%s not found)\n' "${HISTORY_FILE}"
    return 0
  fi

  current_lines="$(current_history_line_count)"
  if [[ "${HISTORY_LINES_AT_ENTER:-unknown}" == "unknown" || "$current_lines" == "unknown" ]]; then
    printf '  New commands since enter: unavailable (history line count unknown)\n'
    return 0
  fi

  delta="$((current_lines - HISTORY_LINES_AT_ENTER))"
  if [[ "$delta" -lt 0 ]]; then
    printf '  New commands since enter: unavailable (history file rotated or truncated)\n'
    return 0
  fi

  printf '  Approx commands added: %s\n' "$delta"
  if [[ "$delta" -eq 0 ]]; then
    return 0
  fi

  start_line="$((HISTORY_LINES_AT_ENTER + 1))"
  shell_name="$(basename "${SESSION_SHELL:-unknown}")"
  raw_preview="$(sed -n "${start_line},\$p" "${HISTORY_FILE}" | tail -n "${history_preview_limit}")"

  if [[ -z "$raw_preview" ]]; then
    return 0
  fi

  printf '  Recent commands:\n'
  case "$shell_name" in
    zsh)
      sed 's/^: [0-9][0-9]*:[0-9][0-9]*;//' <<<"$raw_preview" | sed 's/^/    /'
      ;;
    *)
      sed 's/^/    /' <<<"$raw_preview"
      ;;
  esac
}

print_summary() {
  local elapsed_seconds elapsed_human
  local current_lid_switch current_lid_ext_power current_idle_action

  elapsed_seconds="$(seconds_since_recorded)"
  elapsed_human="$(format_duration "$elapsed_seconds")"
  current_lid_switch="$(loginctl show-logind --property=HandleLidSwitch --value 2>/dev/null || true)"
  current_lid_ext_power="$(loginctl show-logind --property=HandleLidSwitchExternalPower --value 2>/dev/null || true)"
  current_idle_action="$(loginctl show-logind --property=IdleAction --value 2>/dev/null || true)"
  [[ -n "$current_lid_switch" ]] || current_lid_switch='unknown'
  [[ -n "$current_lid_ext_power" ]] || current_lid_ext_power='unknown'
  [[ -n "$current_idle_action" ]] || current_idle_action='unknown'

  cat <<EOF

Saved server-mode state
  Recorded at: ${RECORDED_AT:-unknown}
  Active for: ${elapsed_human}
  Session user: ${SESSION_USER:-unknown}
  Session shell: ${SESSION_SHELL:-unknown}
  SSH service: ${SSH_SERVICE}
  tailscaled enabled before enter: ${PRE_TAILSCALED_ENABLED}
  tailscaled active before enter: ${PRE_TAILSCALED_ACTIVE}
  ${SSH_SERVICE} enabled before enter: ${PRE_SSH_ENABLED}
  ${SSH_SERVICE} active before enter: ${PRE_SSH_ACTIVE}
  HandleLidSwitch before enter: ${PRE_LOGIND_HANDLE_LID_SWITCH:-unknown}
  HandleLidSwitchExternalPower before enter: ${PRE_LOGIND_HANDLE_LID_SWITCH_EXTERNAL_POWER:-unknown}
  IdleAction before enter: ${PRE_LOGIND_IDLE_ACTION:-unknown}
  Services were managed on enter: ${ENTER_ENSURED_SERVICES:-1}
  Logind policy was managed on enter: ${ENTER_APPLIED_LOGIND_POLICY:-1}
  History file: ${HISTORY_FILE:-unknown}

Current service state
  tailscaled enabled: $(service_enabled_state tailscaled)
  tailscaled active: $(service_state tailscaled)
  ${SSH_SERVICE} enabled: $(service_enabled_state "${SSH_SERVICE}")
  ${SSH_SERVICE} active: $(service_state "${SSH_SERVICE}")
  HandleLidSwitch: ${current_lid_switch}
  HandleLidSwitchExternalPower: ${current_lid_ext_power}
  IdleAction: ${current_idle_action}
EOF

  print_history_preview
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[[ "${EUID}" -eq 0 ]] || die "run this script with sudo or as root"
command -v systemctl >/dev/null 2>&1 || die "systemctl is required"

load_state
print_summary

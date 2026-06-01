#!/usr/bin/env bash

set -euo pipefail

require_ac=0
dry_run=0
ensure_services=1
apply_logind_override=1
state_dir="/var/lib/remote-terminal-server-mode"
state_file="${state_dir}/state.env"
logind_conf_dir="/etc/systemd/logind.conf.d"
managed_logind_conf="${logind_conf_dir}/remote-terminal-server-mode.conf"
backup_logind_conf="${state_dir}/logind.conf.before-enter"

usage() {
  cat <<'EOF'
Usage: enter-server-mode.sh [--require-ac] [--dry-run] [--skip-services]
                            [--skip-logind-policy] [--help]

Prepare a Linux laptop for safer unattended remote access by verifying power
state, ensuring core remote-access services are enabled and running, applying a
temporary logind policy that reduces suspend risk, and printing a short status
summary.

Options:
  --require-ac          Exit with an error if AC power is not detected.
  --dry-run             Print the actions that would be taken without changing
                        services or logind policy.
  --skip-services       Do not enable or start tailscaled or SSH.
  --skip-logind-policy  Do not apply the temporary logind suspend override.
  --help                Show this help text.
EOF
}

log() {
  printf '[server-mode] %s\n' "$*"
}

warn() {
  printf '[server-mode] warning: %s\n' "$*" >&2
}

die() {
  printf '[server-mode] error: %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

detect_ssh_service() {
  local candidate

  for candidate in sshd ssh; do
    if systemctl cat "${candidate}.service" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

detect_ac_power_state() {
  local supply type_file online_file type_value online_value found_supply=0

  shopt -s nullglob
  for supply in /sys/class/power_supply/*; do
    type_file="${supply}/type"
    online_file="${supply}/online"

    [[ -f "$type_file" ]] || continue
    type_value="$(<"$type_file")"

    case "$type_value" in
      Mains|USB|USB_C)
        found_supply=1
        if [[ -f "$online_file" ]]; then
          online_value="$(<"$online_file")"
          if [[ "$online_value" == "1" ]]; then
            printf 'online\n'
            shopt -u nullglob
            return 0
          fi
        fi
        ;;
    esac
  done
  shopt -u nullglob

  if [[ "$found_supply" -eq 1 ]]; then
    printf 'offline\n'
  else
    printf 'unknown\n'
  fi
}

get_logind_value() {
  local property value

  property="$1"
  value="$(loginctl show-logind --property="$property" --value 2>/dev/null || true)"

  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf 'unknown\n'
  fi
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

detect_session_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi

  logname 2>/dev/null || printf 'root\n'
}

detect_user_home() {
  local user_name

  user_name="$1"
  if [[ "$user_name" == "root" ]]; then
    printf '/root\n'
    return 0
  fi

  getent passwd "$user_name" | cut -d: -f6
}

detect_user_shell() {
  local user_name

  user_name="$1"
  getent passwd "$user_name" | cut -d: -f7
}

detect_history_file() {
  local user_home user_shell

  user_home="$1"
  user_shell="$2"

  case "$user_shell" in
    */bash|bash)
      printf '%s/.bash_history\n' "$user_home"
      ;;
    */zsh|zsh)
      printf '%s/.zsh_history\n' "$user_home"
      ;;
    */fish|fish)
      printf '%s/.local/share/fish/fish_history\n' "$user_home"
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

history_line_count() {
  local history_file

  history_file="$1"
  if [[ "$history_file" == "unknown" || ! -f "$history_file" ]]; then
    printf 'unknown\n'
  else
    wc -l <"$history_file" | tr -d ' '
  fi
}

write_state_file() {
  local ssh_service pre_tailscaled_enabled pre_tailscaled_active pre_ssh_enabled pre_ssh_active
  local session_user session_home session_shell history_file history_lines
  local pre_lid_switch pre_lid_ext_power pre_idle_action pre_managed_logind_conf_exists
  local recorded_ensure_services recorded_apply_logind_override

  ssh_service="$1"
  pre_tailscaled_enabled="$2"
  pre_tailscaled_active="$3"
  pre_ssh_enabled="$4"
  pre_ssh_active="$5"
  session_user="$6"
  session_home="$7"
  session_shell="$8"
  history_file="$9"
  history_lines="${10}"
  pre_lid_switch="${11}"
  pre_lid_ext_power="${12}"
  pre_idle_action="${13}"
  pre_managed_logind_conf_exists="${14}"
  recorded_ensure_services="${15}"
  recorded_apply_logind_override="${16}"

  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run] mkdir -p %s\n' "$state_dir"
    printf '[dry-run] write %s\n' "$state_file"
    return 0
  fi

  mkdir -p "$state_dir"
  cat >"$state_file" <<EOF
SSH_SERVICE=${ssh_service}
PRE_TAILSCALED_ENABLED=${pre_tailscaled_enabled}
PRE_TAILSCALED_ACTIVE=${pre_tailscaled_active}
PRE_SSH_ENABLED=${pre_ssh_enabled}
PRE_SSH_ACTIVE=${pre_ssh_active}
SESSION_USER=${session_user}
SESSION_HOME=${session_home}
SESSION_SHELL=${session_shell}
HISTORY_FILE=${history_file}
HISTORY_LINES_AT_ENTER=${history_lines}
PRE_LOGIND_HANDLE_LID_SWITCH=${pre_lid_switch}
PRE_LOGIND_HANDLE_LID_SWITCH_EXTERNAL_POWER=${pre_lid_ext_power}
PRE_LOGIND_IDLE_ACTION=${pre_idle_action}
PRE_MANAGED_LOGIND_CONF_EXISTS=${pre_managed_logind_conf_exists}
ENTER_ENSURED_SERVICES=${recorded_ensure_services}
ENTER_APPLIED_LOGIND_POLICY=${recorded_apply_logind_override}
MANAGED_LOGIND_CONF=${managed_logind_conf}
BACKUP_LOGIND_CONF=${backup_logind_conf}
RECORDED_AT=$(date -Iseconds)
EOF
}

backup_existing_logind_conf() {
  if [[ "$dry_run" -eq 1 ]]; then
    if [[ -f "$managed_logind_conf" ]]; then
      printf '[dry-run] cp %s %s\n' "$managed_logind_conf" "$backup_logind_conf"
    fi
    return 0
  fi

  mkdir -p "$state_dir"
  rm -f "$backup_logind_conf"
  if [[ -f "$managed_logind_conf" ]]; then
    cp "$managed_logind_conf" "$backup_logind_conf"
  fi
}

apply_logind_policy() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run] mkdir -p %s\n' "$logind_conf_dir"
    printf '[dry-run] write %s\n' "$managed_logind_conf"
    printf '[dry-run] systemctl restart systemd-logind\n'
    return 0
  fi

  mkdir -p "$logind_conf_dir"
  cat >"$managed_logind_conf" <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
IdleAction=ignore
EOF

  systemctl restart systemd-logind
}

get_tailscale_ip() {
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null | head -n 1 || true
  fi
}

print_summary() {
  local ssh_service tailscale_ip

  ssh_service="$1"
  tailscale_ip="$(get_tailscale_ip)"
  [[ -n "$tailscale_ip" ]] || tailscale_ip='unknown'

  cat <<EOF

Server mode entered
  Recorded at: $(date -Iseconds)
  Hostname: $(hostname)
  AC power: ${ac_power_state}
  tailscaled: $(service_state tailscaled) / $(service_enabled_state tailscaled)
  ${ssh_service}: $(service_state "$ssh_service") / $(service_enabled_state "$ssh_service")
  Tailscale IP: ${tailscale_ip}
  HandleLidSwitch: $(get_logind_value HandleLidSwitch)
  HandleLidSwitchExternalPower: $(get_logind_value HandleLidSwitchExternalPower)
  IdleAction: $(get_logind_value IdleAction)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-ac)
      require_ac=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    --skip-services)
      ensure_services=0
      ;;
    --skip-logind-policy)
      apply_logind_override=0
      ;;
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

ssh_service="$(detect_ssh_service)" || die "could not find sshd.service or ssh.service"
ac_power_state="$(detect_ac_power_state)"
pre_tailscaled_enabled="$(service_enabled_state tailscaled)"
pre_tailscaled_active="$(service_state tailscaled)"
pre_ssh_enabled="$(service_enabled_state "$ssh_service")"
pre_ssh_active="$(service_state "$ssh_service")"
session_user="$(detect_session_user)"
session_home="$(detect_user_home "$session_user")"
session_shell="$(detect_user_shell "$session_user")"
history_file="$(detect_history_file "$session_home" "$session_shell")"
history_lines="$(history_line_count "$history_file")"

[[ -n "$session_home" ]] || session_home='unknown'
[[ -n "$session_shell" ]] || session_shell='unknown'

log "detected SSH service: ${ssh_service}"

case "$ac_power_state" in
  online)
    log "AC power detected"
    ;;
  offline)
    if [[ "$require_ac" -eq 1 ]]; then
      die "AC power not detected and --require-ac was requested"
    fi
    warn "AC power not detected"
    ;;
  unknown)
    if [[ "$require_ac" -eq 1 ]]; then
      die "AC power state is unknown and --require-ac was requested"
    fi
    warn "AC power state is unknown"
    ;;
esac

log "recording pre-change service state in ${state_file}"
backup_existing_logind_conf
write_state_file \
  "$ssh_service" \
  "$pre_tailscaled_enabled" \
  "$pre_tailscaled_active" \
  "$pre_ssh_enabled" \
  "$pre_ssh_active" \
  "$session_user" \
  "$session_home" \
  "$session_shell" \
  "$history_file" \
  "$history_lines" \
  "$(get_logind_value HandleLidSwitch)" \
  "$(get_logind_value HandleLidSwitchExternalPower)" \
  "$(get_logind_value IdleAction)" \
  "$([[ -f "$managed_logind_conf" ]] && printf '1' || printf '0')" \
  "$ensure_services" \
  "$apply_logind_override"

if [[ "$ensure_services" -eq 1 ]]; then
  log "ensuring tailscaled is enabled and started"
  run_cmd systemctl enable tailscaled
  run_cmd systemctl start tailscaled

  log "ensuring ${ssh_service} is enabled and started"
  run_cmd systemctl enable "$ssh_service"
  run_cmd systemctl start "$ssh_service"
else
  log "skipping service enable/start per user request"
fi

if [[ "$apply_logind_override" -eq 1 ]]; then
  log "applying temporary logind policy for unattended mode"
  apply_logind_policy
else
  log "skipping temporary logind policy per user request"
fi

print_summary "$ssh_service"

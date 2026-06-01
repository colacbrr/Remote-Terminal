#!/usr/bin/env bash

set -euo pipefail

dry_run=0
keep_state=0
post_action="none"
state_dir="/var/lib/remote-terminal-server-mode"
state_file="${state_dir}/state.env"
default_logind_conf_dir="/etc/systemd/logind.conf.d"

usage() {
  cat <<'EOF'
Usage: exit-server-mode.sh [--dry-run] [--keep-state] [--reboot]
                           [--poweroff] [--help]

Leave server mode by restoring the saved service state and logind policy
captured by enter-server-mode.sh. By default, the saved state file is removed
after a successful restore.

Options:
  --dry-run     Print the actions that would be taken.
  --keep-state  Preserve the saved state file after restoring services.
  --reboot      Reboot the laptop after exiting server mode.
  --poweroff    Power off the laptop after exiting server mode.
  --help        Show this help text.
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

print_summary() {
  local current_lid_switch current_lid_ext_power current_idle_action

  current_lid_switch="$(loginctl show-logind --property=HandleLidSwitch --value 2>/dev/null || true)"
  current_lid_ext_power="$(loginctl show-logind --property=HandleLidSwitchExternalPower --value 2>/dev/null || true)"
  current_idle_action="$(loginctl show-logind --property=IdleAction --value 2>/dev/null || true)"
  [[ -n "$current_lid_switch" ]] || current_lid_switch='unknown'
  [[ -n "$current_lid_ext_power" ]] || current_lid_ext_power='unknown'
  [[ -n "$current_idle_action" ]] || current_idle_action='unknown'

  cat <<EOF

Exiting server mode
  Recorded at: ${RECORDED_AT:-unknown}
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

Current service state before restore
  tailscaled enabled: $(service_enabled_state tailscaled)
  tailscaled active: $(service_state tailscaled)
  ${SSH_SERVICE} enabled: $(service_enabled_state "${SSH_SERVICE}")
  ${SSH_SERVICE} active: $(service_state "${SSH_SERVICE}")
  HandleLidSwitch: ${current_lid_switch}
  HandleLidSwitchExternalPower: ${current_lid_ext_power}
  IdleAction: ${current_idle_action}
EOF
}

restore_service_enabled_state() {
  local service desired

  service="$1"
  desired="$2"

  case "$desired" in
    enabled)
      log "ensuring ${service} is enabled"
      run_cmd systemctl enable "$service"
      ;;
    disabled)
      log "disabling ${service}"
      run_cmd systemctl disable "$service"
      ;;
    *)
      warn "cannot restore enabled state for ${service}; recorded value was ${desired}"
      ;;
  esac
}

restore_service_active_state() {
  local service desired

  service="$1"
  desired="$2"

  case "$desired" in
    active)
      log "ensuring ${service} is running"
      run_cmd systemctl start "$service"
      ;;
    inactive|failed)
      log "stopping ${service}"
      run_cmd systemctl stop "$service"
      ;;
    *)
      warn "cannot restore active state for ${service}; recorded value was ${desired}"
      ;;
  esac
}

restore_logind_policy() {
  local managed_conf_path backup_conf_path pre_exists

  if [[ "${ENTER_APPLIED_LOGIND_POLICY:-1}" != "1" ]]; then
    log "logind policy was not changed on enter; skipping logind restore"
    return 0
  fi

  managed_conf_path="${MANAGED_LOGIND_CONF:-${default_logind_conf_dir}/remote-terminal-server-mode.conf}"
  backup_conf_path="${BACKUP_LOGIND_CONF:-${state_dir}/logind.conf.before-enter}"
  pre_exists="${PRE_MANAGED_LOGIND_CONF_EXISTS:-0}"

  if [[ "$pre_exists" == "1" ]]; then
    if [[ -f "$backup_conf_path" ]]; then
      log "restoring previous managed logind drop-in"
      run_cmd cp "$backup_conf_path" "$managed_conf_path"
    else
      warn "expected backup logind config at ${backup_conf_path}, leaving ${managed_conf_path} unchanged"
    fi
  else
    if [[ -f "$managed_conf_path" ]]; then
      log "removing temporary logind drop-in ${managed_conf_path}"
      run_cmd rm -f "$managed_conf_path"
    fi
  fi

  log "restarting systemd-logind to apply restored policy"
  run_cmd systemctl restart systemd-logind

  if [[ "$keep_state" -eq 0 && "$dry_run" -eq 0 ]]; then
    rm -f "$backup_conf_path"
  fi
}

remove_state_file() {
  if [[ "$keep_state" -eq 1 ]]; then
    log "keeping saved state file at ${state_file}"
    return 0
  fi

  log "removing saved state file ${state_file}"
  run_cmd rm -f "$state_file"
}

perform_post_action() {
  case "$post_action" in
    none)
      return 0
      ;;
    reboot)
      log "rebooting laptop after exiting server mode"
      run_cmd systemctl reboot
      ;;
    poweroff)
      log "powering off laptop after exiting server mode"
      run_cmd systemctl poweroff
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --keep-state)
      keep_state=1
      ;;
    --reboot)
      post_action="reboot"
      ;;
    --poweroff)
      post_action="poweroff"
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

load_state
print_summary

log "restoring saved service state"
if [[ "${ENTER_ENSURED_SERVICES:-1}" == "1" ]]; then
  restore_service_active_state tailscaled "${PRE_TAILSCALED_ACTIVE}"
  restore_service_enabled_state tailscaled "${PRE_TAILSCALED_ENABLED}"
  restore_service_active_state "${SSH_SERVICE}" "${PRE_SSH_ACTIVE}"
  restore_service_enabled_state "${SSH_SERVICE}" "${PRE_SSH_ENABLED}"
else
  log "services were not changed on enter; skipping service restore"
fi
restore_logind_policy
remove_state_file
perform_post_action

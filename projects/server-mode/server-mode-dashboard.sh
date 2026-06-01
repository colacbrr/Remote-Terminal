#!/usr/bin/env bash

set -euo pipefail

watch_interval=0
state_file="/var/lib/remote-terminal-server-mode/state.env"
state_dir="/var/lib/remote-terminal-server-mode"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exit_script="${script_dir}/exit-server-mode.sh"
tty_state=""
use_color=0
color_reset=""
color_dim=""
color_ok=""
color_warn=""
color_bad=""
color_accent=""

usage() {
  cat <<'EOF'
Usage: server-mode-dashboard.sh [--watch SECONDS] [--help]

Show a compact local dashboard with the laptop's current server-mode phase,
service health, power state, and a few machine stats.

Options:
  --watch SECONDS  Refresh continuously every N seconds.
  --help           Show this help text.
EOF
}

die() {
  printf '[server-mode-dashboard] error: %s\n' "$*" >&2
  exit 1
}

stdout_is_tty() {
  [[ -t 1 ]]
}

stdin_is_tty() {
  [[ -t 0 ]]
}

restore_tty() {
  if [[ -n "$tty_state" ]] && stdin_is_tty; then
    stty "$tty_state"
    tty_state=""
  fi
}

configure_tty_for_keys() {
  if ! stdin_is_tty; then
    return 0
  fi

  tty_state="$(stty -g)"
  trap restore_tty EXIT INT TERM
  stty -ixon -echo -icanon min 0 time 0
}

can_restore_server_mode() {
  [[ -f "$state_file" && "${EUID}" -eq 0 ]]
}

setup_colors() {
  if stdout_is_tty && command -v tput >/dev/null 2>&1; then
    use_color=1
    color_reset="$(tput sgr0)"
    color_dim="$(tput dim)"
    color_ok="$(tput setaf 2)"
    color_warn="$(tput setaf 3)"
    color_bad="$(tput setaf 1)"
    color_accent="$(tput setaf 6)"
  fi
}

paint() {
  local color text
  color="$1"
  text="$2"

  if [[ "$use_color" -eq 1 ]]; then
    printf '%s%s%s' "$color" "$text" "$color_reset"
  else
    printf '%s' "$text"
  fi
}

status_badge() {
  local value normalized
  value="$1"
  normalized="${value,,}"

  case "$normalized" in
    active|enabled|online|full|charging)
      paint "$color_ok" "[$value]"
      ;;
    unknown|not\ assigned|not\ detected)
      paint "$color_warn" "[$value]"
      ;;
    inactive|disabled|offline|discharging|dead)
      paint "$color_bad" "[$value]"
      ;;
    *)
      paint "$color_accent" "[$value]"
      ;;
  esac
}

print_rule() {
  printf '%s\n' '+------------------------------------------------------------------+'
}

print_line() {
  printf '| %-64s |\n' "$1"
}

bar_for_percent() {
  local percent filled empty bar
  percent="$1"
  if [[ ! "$percent" =~ ^[0-9]+$ ]]; then
    printf 'n/a'
    return 0
  fi

  if [[ "$percent" -lt 0 ]]; then
    percent=0
  elif [[ "$percent" -gt 100 ]]; then
    percent=100
  fi

  filled=$((percent / 10))
  empty=$((10 - filled))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  bar="${bar}$(printf '%*s' "$empty" '' | tr ' ' '-')"
  printf '[%s] %s%%' "$bar" "$percent"
}

service_state() {
  local service
  service="$1"
  systemctl is-active "$service" 2>/dev/null || printf 'unknown'
}

service_enabled_state() {
  local service
  service="$1"
  systemctl is-enabled "$service" 2>/dev/null || printf 'unknown'
}

detect_ssh_service() {
  local candidate
  for candidate in sshd ssh; do
    if systemctl cat "${candidate}.service" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'sshd\n'
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

read_battery_summary() {
  local battery capacity_file status_file capacity status

  shopt -s nullglob
  for battery in /sys/class/power_supply/BAT*; do
    capacity_file="${battery}/capacity"
    status_file="${battery}/status"
    capacity="unknown"
    status="unknown"

    [[ -f "$capacity_file" ]] && capacity="$(<"$capacity_file")%"
    [[ -f "$status_file" ]] && status="$(<"$status_file")"
    printf '%s (%s)\n' "$capacity" "$status"
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob

  printf 'not detected\n'
}

read_battery_percent() {
  local battery capacity_file

  shopt -s nullglob
  for battery in /sys/class/power_supply/BAT*; do
    capacity_file="${battery}/capacity"
    if [[ -f "$capacity_file" ]]; then
      <"$capacity_file" tr -d '\n'
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  printf 'unknown\n'
}

get_load_average() {
  awk '{print $1 " " $2 " " $3}' /proc/loadavg
}

get_memory_summary() {
  awk '
    /^MemTotal:/ { total_mb = int($2 / 1024) }
    /^MemAvailable:/ { avail_mb = int($2 / 1024) }
    END {
      used_mb = total_mb - avail_mb
      printf "%s MiB / %s MiB", used_mb, total_mb
    }
  ' /proc/meminfo
}

get_memory_percent() {
  awk '
    /^MemTotal:/ { total = int($2 / 1024) }
    /^MemAvailable:/ { avail = int($2 / 1024) }
    END {
      if (total > 0) {
        used = total - avail
        printf "%d", int((used * 100) / total)
      } else {
        printf "unknown"
      }
    }
  ' /proc/meminfo
}

get_uptime() {
  local total days hours minutes
  total="$(cut -d. -f1 /proc/uptime)"
  days="$((total / 86400))"
  hours="$(((total / 3600) % 24))"
  minutes="$(((total / 60) % 60))"

  if [[ "$days" -gt 0 ]]; then
    printf '%sd %02dh %02dm\n' "$days" "$hours" "$minutes"
  else
    printf '%02dh %02dm\n' "$hours" "$minutes"
  fi
}

get_tailscale_ip() {
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null | head -n 1 || true
  fi
}

read_phase() {
  if [[ -f "$state_file" ]]; then
    awk -F= '
      /^RECORDED_AT=/ { ts=$2 }
      END {
        if (ts == "") ts = "unknown"
        printf "%s|%s\n", "active", ts
      }
    ' "$state_file"
  else
    printf 'not-entered|unknown\n'
  fi
}

render_dashboard() {
  local ssh_service phase_info phase phase_at tailscale_ip controls
  local tailscaled_active tailscaled_enabled ssh_active ssh_enabled
  local ac_state battery_summary battery_percent memory_summary memory_percent
  local uptime_summary load_summary refreshed_at

  ssh_service="$(detect_ssh_service)"
  phase_info="$(read_phase)"
  phase="${phase_info%%|*}"
  phase_at="${phase_info#*|}"
  tailscale_ip="$(get_tailscale_ip)"
  [[ -n "$tailscale_ip" ]] || tailscale_ip="not assigned"
  tailscaled_active="$(service_state tailscaled)"
  tailscaled_enabled="$(service_enabled_state tailscaled)"
  ssh_active="$(service_state "$ssh_service")"
  ssh_enabled="$(service_enabled_state "$ssh_service")"
  ac_state="$(detect_ac_power_state)"
  battery_summary="$(read_battery_summary)"
  battery_percent="$(read_battery_percent)"
  memory_summary="$(get_memory_summary)"
  memory_percent="$(get_memory_percent)"
  uptime_summary="$(get_uptime)"
  load_summary="$(get_load_average)"
  refreshed_at="$(date '+%F %T')"

  if stdout_is_tty; then
    printf '\033[H\033[J'
  elif [[ "$watch_interval" -gt 0 ]]; then
    printf '\n[%s] dashboard snapshot\n' "$(date '+%F %T')"
  fi

  controls='Ctrl+Q or q: quit'
  if can_restore_server_mode; then
    controls="${controls} | x: restore state and exit server mode"
  fi

  print_rule
  print_line "$(paint "$color_accent" 'REMOTE TERMINAL CONTROL PANEL')"
  print_line "Host: $(hostname)   Refreshed: ${refreshed_at}"
  print_line "Phase: $(status_badge "$phase")   Updated: ${phase_at}"
  print_rule
  print_line "CONNECTIVITY"
  print_line "tailscaled : $(status_badge "$tailscaled_active") / $(status_badge "$tailscaled_enabled")"
  print_line "${ssh_service}      : $(status_badge "$ssh_active") / $(status_badge "$ssh_enabled")"
  print_line "Tailscale IP: ${tailscale_ip}"
  print_rule
  print_line "POWER"
  print_line "AC          : $(status_badge "$ac_state")"
  print_line "Battery     : ${battery_summary}"
  print_line "Battery bar : $(bar_for_percent "$battery_percent")"
  print_rule
  print_line "SYSTEM"
  print_line "Uptime      : ${uptime_summary}"
  print_line "Load avg    : ${load_summary}"
  print_line "Memory      : ${memory_summary}"
  print_line "Memory bar  : $(bar_for_percent "$memory_percent")"
  print_rule
  print_line "COMMANDS"
  print_line "tailscale status"
  print_line "systemctl status tailscaled --no-pager"
  print_line "systemctl status ${ssh_service} --no-pager"
  print_rule
  print_line "CONTROLS"
  print_line "${controls}"
  print_rule

  if [[ "$phase" == "not-entered" ]]; then
    printf '%s\n' "$(paint "$color_dim" 'Note: phase stays at not-entered until sudo ./enter-server-mode.sh writes state.')"
  fi
}

handle_keypress() {
  local key

  if ! stdin_is_tty; then
    return 1
  fi

  IFS= read -rsn1 key || true
  case "$key" in
    $'\x11'|q|Q)
      return 10
      ;;
    x|X)
      if can_restore_server_mode; then
        restore_tty
        "$exit_script"
        return 11
      fi
      ;;
  esac

  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      shift
      [[ $# -gt 0 ]] || die "missing value for --watch"
      watch_interval="$1"
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

setup_colors

if [[ "$watch_interval" -gt 0 ]]; then
  if stdout_is_tty && stdin_is_tty; then
    configure_tty_for_keys
  fi

  while true; do
    render_dashboard
    if stdout_is_tty && stdin_is_tty; then
      local_end_time=$((SECONDS + watch_interval))
      while [[ "$SECONDS" -lt "$local_end_time" ]]; do
        if handle_keypress; then
          sleep 0.1
          continue
        fi

        key_status=$?
        if [[ "$key_status" -eq 10 || "$key_status" -eq 11 ]]; then
          exit 0
        fi
      done
    else
      sleep "$watch_interval"
    fi
  done
else
  render_dashboard
fi

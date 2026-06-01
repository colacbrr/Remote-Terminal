#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="/var/lib/remote-terminal-server-mode"
STATE_FILE="${STATE_DIR}/state.env"
LOGIND_DROPIN_DIR="/etc/systemd/logind.conf.d"
LOGIND_DROPIN_FILE="${LOGIND_DROPIN_DIR}/50-remote-terminal-server-mode.conf"
HEALTH_FILE="${STATE_DIR}/health.env"
WEB_HOST="127.0.0.1"
WEB_PORT="8788"
WEB_PID_FILE="${STATE_DIR}/server-mode-web.pid"
WEB_LOG_FILE="${STATE_DIR}/server-mode-web.log"

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
      tr -d '\n' <"$capacity_file"
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

get_root_disk_usage() {
  df -h / 2>/dev/null | awk 'NR==2 { printf "%s used / %s (%s)", $3, $2, $5 }'
}

get_root_disk_percent() {
  df -P / 2>/dev/null | awk 'NR==2 { gsub(/%/, "", $5); print $5 }'
}

get_cpu_temperature() {
  local zone temp_file temp_raw

  shopt -s nullglob
  for zone in /sys/class/thermal/thermal_zone*; do
    temp_file="${zone}/temp"
    [[ -f "$temp_file" ]] || continue
    temp_raw="$(<"$temp_file")"
    if [[ "$temp_raw" =~ ^[0-9]+$ ]] && [[ "$temp_raw" -gt 1000 ]]; then
      awk "BEGIN { printf \"%.1f C\", ${temp_raw}/1000 }"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  printf 'unknown\n'
}

get_firewall_warning() {
  local ufw_output

  if command -v ufw >/dev/null 2>&1; then
    ufw_output="$(ufw status 2>/dev/null || true)"
    if grep -q '^Status: inactive' <<<"$ufw_output"; then
      printf 'ufw inactive; host firewall is effectively open unless another firewall is active\n'
      return 0
    fi

    if grep -Eq '(^|[[:space:]])22(/tcp)?[[:space:]]+ALLOW[[:space:]]+Anywhere' <<<"$ufw_output"; then
      printf 'SSH is allowed from Anywhere in ufw; Tailscale-only access is safer\n'
      return 0
    fi

    printf 'none\n'
    return 0
  fi

  printf 'unknown\n'
}

load_state_if_present() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

load_health_if_present() {
  if [[ -f "$HEALTH_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$HEALTH_FILE"
  fi
}

shell_assign() {
  local key value
  key="$1"
  value="${2-}"
  printf '%s=%q\n' "$key" "$value"
}

write_health_file() {
  local status warning checked_at

  status="$1"
  warning="$2"
  checked_at="$3"

  mkdir -p "$STATE_DIR"
  {
    shell_assign "HEALTH_STATUS" "$status"
    shell_assign "HEALTH_WARNING" "$warning"
    shell_assign "HEALTH_LAST_OK_AT" "$checked_at"
  } >"$HEALTH_FILE"
}

tailnet_dns_name() {
  if ! command -v tailscale >/dev/null 2>&1; then
    printf 'unknown\n'
    return 0
  fi

  tailscale status --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    name = data.get("Self", {}).get("DNSName", "")
    print(name.rstrip(".") if name else "unknown")
except Exception:
    print("unknown")
' || printf 'unknown\n'
}

published_dashboard_url() {
  local dns_name

  dns_name="$(tailnet_dns_name)"
  if [[ -z "$dns_name" || "$dns_name" == "unknown" ]]; then
    printf 'unknown\n'
  else
    printf 'https://%s\n' "$dns_name"
  fi
}

serve_status_summary() {
  if ! command -v tailscale >/dev/null 2>&1; then
    printf 'unavailable\n'
    return 0
  fi

  tailscale serve status 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/ $//'
}

#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/server-mode-common.sh"

json_mode=0

usage() {
  cat <<'EOF'
Usage: server-mode-status.sh [--json] [--help]

Print the current server-mode status, including service health, power, basic
machine stats, and recent persisted phase information.
EOF
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_mode=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      printf 'error: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

load_state_if_present
load_health_if_present

host_name="$(hostname)"
ssh_service="$(detect_ssh_service)"
tailscaled_active="$(service_state tailscaled)"
tailscaled_enabled="$(service_enabled_state tailscaled)"
ssh_active="$(service_state "$ssh_service")"
ssh_enabled="$(service_enabled_state "$ssh_service")"
ac_state="$(detect_ac_power_state)"
battery_summary="$(read_battery_summary)"
battery_percent="$(read_battery_percent)"
memory_summary="$(get_memory_summary)"
memory_percent="$(get_memory_percent)"
disk_summary="$(get_root_disk_usage)"
disk_percent="$(get_root_disk_percent)"
load_avg="$(get_load_average)"
uptime_summary="$(get_uptime)"
tailscale_ip="$(get_tailscale_ip)"
cpu_temp="$(get_cpu_temperature)"
firewall_warning="$(get_firewall_warning)"
publish_url="$(published_dashboard_url)"
serve_status="$(serve_status_summary)"
web_ui_status="stopped"
phase="not-entered"
phase_at="${RECORDED_AT:-unknown}"
health_status="unknown"
health_last_ok="unknown"
health_warning="${HEALTH_WARNING:-unknown}"

if [[ -f "$STATE_FILE" ]]; then
  phase="active"
fi

if [[ "$tailscaled_active" == "active" && "$ssh_active" == "active" ]]; then
  health_status="healthy"
  if [[ -f "$STATE_FILE" ]]; then
    health_last_ok="${RECORDED_AT:-unknown}"
  fi
elif [[ "$tailscaled_active" == "unknown" || "$ssh_active" == "unknown" ]]; then
  health_status="unknown"
else
  health_status="degraded"
fi

if [[ "$health_warning" == "unknown" || -z "$health_warning" ]]; then
  health_warning="$firewall_warning"
fi

if [[ -f "$WEB_PID_FILE" ]]; then
  web_pid="$(<"$WEB_PID_FILE")"
  if [[ -n "$web_pid" ]] && kill -0 "$web_pid" 2>/dev/null; then
    web_ui_status="running"
  fi
fi

if [[ "$json_mode" -eq 1 ]]; then
  cat <<EOF
{
  "hostname": $(printf '%s' "$host_name" | json_escape),
  "phase": $(printf '%s' "$phase" | json_escape),
  "phase_updated_at": $(printf '%s' "$phase_at" | json_escape),
  "health_status": $(printf '%s' "$health_status" | json_escape),
  "health_last_ok_at": $(printf '%s' "$health_last_ok" | json_escape),
  "health_warning": $(printf '%s' "$health_warning" | json_escape),
  "tailscaled_active": $(printf '%s' "$tailscaled_active" | json_escape),
  "tailscaled_enabled": $(printf '%s' "$tailscaled_enabled" | json_escape),
  "ssh_service": $(printf '%s' "$ssh_service" | json_escape),
  "ssh_active": $(printf '%s' "$ssh_active" | json_escape),
  "ssh_enabled": $(printf '%s' "$ssh_enabled" | json_escape),
  "tailscale_ip": $(printf '%s' "$tailscale_ip" | json_escape),
  "ac_state": $(printf '%s' "$ac_state" | json_escape),
  "battery_summary": $(printf '%s' "$battery_summary" | json_escape),
  "battery_percent": $(printf '%s' "$battery_percent" | json_escape),
  "memory_summary": $(printf '%s' "$memory_summary" | json_escape),
  "memory_percent": $(printf '%s' "$memory_percent" | json_escape),
  "disk_summary": $(printf '%s' "$disk_summary" | json_escape),
  "disk_percent": $(printf '%s' "$disk_percent" | json_escape),
  "load_average": $(printf '%s' "$load_avg" | json_escape),
  "uptime": $(printf '%s' "$uptime_summary" | json_escape),
  "cpu_temperature": $(printf '%s' "$cpu_temp" | json_escape),
  "firewall_warning": $(printf '%s' "$firewall_warning" | json_escape),
  "web_ui_status": $(printf '%s' "$web_ui_status" | json_escape),
  "publish_url": $(printf '%s' "$publish_url" | json_escape),
  "serve_status": $(printf '%s' "$serve_status" | json_escape)
}
EOF
  exit 0
fi

cat <<EOF
Server mode status
  Hostname: ${host_name}
  Phase: ${phase}
  Phase updated at: ${phase_at}
  Health: ${health_status}
  Last healthy at: ${health_last_ok}
  Health warning: ${health_warning}

Connectivity
  tailscaled: ${tailscaled_active} / ${tailscaled_enabled}
  ${ssh_service}: ${ssh_active} / ${ssh_enabled}
  Tailscale IP: ${tailscale_ip}

Power
  AC: ${ac_state}
  Battery: ${battery_summary}

System
  Uptime: ${uptime_summary}
  Load avg: ${load_avg}
  Memory: ${memory_summary}
  Disk: ${disk_summary}
  CPU temp: ${cpu_temp}
  Firewall warning: ${firewall_warning}
  Web UI: ${web_ui_status}
  Published URL: ${publish_url}
  Serve status: ${serve_status}
EOF

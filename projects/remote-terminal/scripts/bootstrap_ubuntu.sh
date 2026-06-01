#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y wireguard openssh-server tmux ufw tailscale

systemctl enable ssh
systemctl start ssh
systemctl enable tailscaled
systemctl start tailscaled

ufw allow 51820/udp
ufw allow OpenSSH

echo
echo "Bootstrap complete."
echo "Next steps:"
echo "  1. Run 'tailscale up' if Tailscale is your access path."
echo "  2. Verify SSH access over the Tailscale IP before hardening further."
echo "  3. Create WireGuard keys on the target host only if you still want native WireGuard."
echo "  4. Review SSH hardening before changing sshd_config."

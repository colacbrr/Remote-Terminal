# Remote Terminal

Secure remote terminal access to a home Linux machine from a phone using
Tailscale, SSH, and `tmux`.

This version of the repo is written as public documentation. It removes
machine-specific details and keeps only the reusable architecture, templates,
and setup flow.

## Goal

Reach a Linux host safely from a phone, run shell commands remotely, and keep
sessions alive without exposing SSH directly to the public internet.

## Recommended Architecture

Primary working architecture:

Phone -> Tailscale -> Linux Host -> SSH -> tmux

This avoids public IPv4 dependency and usually works even when the home network
is behind double NAT or ISP-side CGNAT.

Optional architecture for networks with real inbound reachability:

Phone -> WireGuard VPN -> Home Router -> Linux Host -> SSH -> tmux

In that model, only WireGuard is exposed publicly and SSH stays behind the VPN.

## Why Tailscale-First

For many home networks, native inbound WireGuard is blocked by conditions
outside the local machine:

- ISP-side CGNAT
- double NAT
- routers that cannot be bridged cleanly
- no stable public IPv4

Tailscale usually solves the actual remote-access problem faster and with less
operational overhead. WireGuard is still documented here because it remains a
good design when the network really allows it.

## Repo Contents

- `documentation.md`
  Detailed architecture, security model, tradeoffs, and implementation phases.
- `setup.md`
  Practical Tailscale-first setup checklist with placeholders.
- `configs/`
  Safe example configuration files only.
- `scripts/`
  Bootstrap scripts for Arch-based and Ubuntu/Debian hosts.
- `roadmap.md`
  How the project evolved from WireGuard-first to Tailscale-first guidance.
- `todo.md`
  Reusable checklist for someone repeating the setup.

## Safety Baseline

- never commit real VPN keys
- never commit real SSH private keys
- do not expose SSH directly to the public internet
- prefer SSH keys over passwords
- treat this repository as documentation and templates, not a secrets store

## Start Here

1. Read [documentation.md](documentation.md).
2. Follow [setup.md](setup.md).
3. Use [scripts/bootstrap_arch.sh](scripts/bootstrap_arch.sh) or
   [scripts/bootstrap_ubuntu.sh](scripts/bootstrap_ubuntu.sh) on the target
   host.
4. Apply [configs/ssh/sshd_config.hardening.example](configs/ssh/sshd_config.hardening.example)
   only after key authentication is confirmed.
5. Keep [configs/wireguard/wg0.conf.example](configs/wireguard/wg0.conf.example)
   as an optional reference for non-CGNAT environments.

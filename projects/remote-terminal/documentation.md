# Remote Terminal Documentation

## Purpose

This project documents a safe and practical way to access a home Linux machine
from a phone. The immediate goal is reliable terminal access without exposing
SSH directly to the public internet.

The recommended default design is:

Phone -> Tailscale -> Linux Host -> SSH -> tmux

WireGuard is still included as a documented option, but mainly for networks
where inbound connectivity is actually available.

## Scope

This repository is for:

- documenting architecture and security decisions
- storing safe example configs and bootstrap scripts
- recording a setup flow that other people can reproduce

This repository is not for:

- storing private keys
- storing production passwords
- storing live router details, public IPs, or personal usernames

## Core Stack

### Host side

- Linux host
- Tailscale for the primary remote-access path
- OpenSSH Server for shell access
- `tmux` for persistent terminal sessions
- `ufw` or another host firewall
- optionally WireGuard for networks with real inbound reachability

### Phone side

- Tailscale iOS app
- SSH client such as Termius, Blink Shell, or Prompt
- optionally WireGuard iOS app

## Security Model

The simplest safe model is:

1. Do not put SSH directly on the public internet.
2. Use a private overlay network or VPN to reach the host.
3. Use SSH keys for shell login.
4. Use `sudo` normally after login rather than trying to bypass local host
   authorization.

Important baseline rules:

1. Never commit real WireGuard private keys.
2. Never commit real SSH private keys.
3. Keep example config files suffixed with `.example`.
4. Prefer documenting commands over storing live secrets.
5. Disable password authentication only after SSH key login is verified.

## Why Tailscale Is Often The Practical Choice

Native inbound WireGuard is a good design when the home network actually
permits inbound reachability. In practice, many home networks do not.

Common blockers:

- ISP-side CGNAT
- double NAT
- a modem/router in front of your own router
- no stable public IPv4

When one or more of those apply, local router configuration alone may not be
enough. Tailscale avoids most of that operational pain and usually gets to a
working result faster.

## Decision Framework

Use Tailscale first when:

- you want the fastest working path
- you are behind CGNAT or double NAT
- you do not want to expose a public service
- you want lower router-maintenance overhead

Use native WireGuard when:

- you have a real reachable public IP or a working IPv6 plan
- you want a fully self-hosted network entry point
- you are comfortable maintaining router/firewall state

## Threat Model

This setup is mainly meant to reduce:

- random internet scanning of SSH
- brute-force login attempts
- weak home-lab exposure patterns
- loss of shell state from mobile disconnects

This setup does not by itself solve:

- host compromise by malware or local users
- stolen unlocked phones
- weak SSH private-key hygiene
- unsafe `sudoers` policy
- router compromise

## Recommended Network Plan

For Tailscale:

- use the tailnet-assigned host IP or MagicDNS hostname
- keep SSH bound to the host and reach it through the tailnet

For WireGuard examples:

- server tunnel IP: `10.8.0.1/24`
- first phone client: `10.8.0.2/32`
- listen port: `51820/UDP`

These are examples, not required values.

## Practical Workflow

1. Install SSH, `tmux`, firewall tooling, and Tailscale on the Linux host.
2. Join the host to the tailnet.
3. Join the phone to the same tailnet.
4. Verify SSH over the Tailscale IP or MagicDNS hostname.
5. Create a dedicated SSH key for the phone client.
6. Harden SSH after key login is confirmed.
7. Use `tmux` for reconnect-safe sessions.

## Common Failure Modes

- Tailscale is installed but not logged in
- `sshd` is not running
- the host firewall blocks port `22`
- MagicDNS is unhealthy, so the raw Tailscale IP must be used first
- WireGuard is configured locally, but the network is still behind CGNAT
- SSH hardening is applied before a second working key-auth session exists

## Validation Checklist

The setup is in good shape when all of these are true:

- the Linux host is online in the tailnet
- the phone is online in the same tailnet
- SSH key authentication works
- password authentication is disabled only after that verification
- `tmux` sessions survive reconnects

## Files In This Project

- [setup.md](setup.md)
- [roadmap.md](roadmap.md)
- [todo.md](todo.md)
- [configs/wireguard/wg0.conf.example](configs/wireguard/wg0.conf.example)
- [configs/ssh/sshd_config.hardening.example](configs/ssh/sshd_config.hardening.example)
- [scripts/bootstrap_arch.sh](scripts/bootstrap_arch.sh)
- [scripts/bootstrap_ubuntu.sh](scripts/bootstrap_ubuntu.sh)

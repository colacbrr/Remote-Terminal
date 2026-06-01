# Remote Terminal Roadmap

## Phase 1: Working Remote Access

Target:

- phone can reach the Linux host
- SSH login works over a private network path
- `tmux` keeps sessions alive

Preferred implementation:

- Tailscale
- SSH keys
- `tmux`

## Phase 2: SSH Hardening

Target:

- password authentication disabled
- root login disabled
- public-key authentication required
- firewall policy reviewed

## Phase 3: Optional Native WireGuard

Only pursue this when the network allows it.

Requirements:

- reachable public IP or a usable IPv6 plan
- router/firewall control
- stable peer management

If the environment is behind CGNAT or difficult double NAT, Tailscale remains
the practical default.

## Phase 4: Reliability Improvements

Target:

- smoother reconnect behavior from the phone
- stable MagicDNS or hostname usage
- cleaner host aliases in SSH config
- documented recovery checks after reboot

## Phase 5: Server Mode Integration

Target:

- one command to prepare the machine for unattended remote use
- verified `tailscaled` and `sshd` state
- reduced risk of suspend or lid-close interruptions

## Decision Update

This project started with a more classic self-hosted idea:

- native WireGuard
- router forwarding
- SSH after the tunnel comes up

That remains technically valid on the right network. For many real home
networks, however, the faster and more reliable answer is:

- use Tailscale first
- keep WireGuard as an optional documented branch

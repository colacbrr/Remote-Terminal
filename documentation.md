# Project Documentation

## Current Scope

This repository covers two related concerns:

1. `projects/remote-terminal/` documents how to establish secure remote shell
   access to a Linux host from a phone.
2. `projects/server-mode/` adds a reversible operational layer for leaving that
   host running at home in a known remote-access state.

## What Exists Now

The implemented workflow is:

1. `projects/remote-terminal/` documents the Tailscale-first architecture,
   setup flow, safe example configs, and bootstrap scripts.
2. `projects/server-mode/enter-server-mode.sh` records the current service
   state.
3. It checks AC power and reports logind power-policy values.
4. It ensures `tailscaled` and the detected SSH service are enabled and
   running.
5. It applies a reversible logind override for lid-close and idle behavior.
6. `projects/server-mode/inspect-server-mode.sh` shows the saved state without
   changing anything.
7. `projects/server-mode/exit-server-mode.sh` restores the saved service state
   and logind policy and removes the saved state file by default.
8. `projects/server-mode/server-mode-ui.sh` provides an interactive
   `whiptail` interface over the same workflows.
9. `projects/server-mode/server-mode-status.sh`,
   `server-mode-dashboard.sh`, and `server-mode-web.py` provide optional local
   status views and controls.

## What Does Not Exist Yet

- Wi-Fi power-saving tuning
- long-run health checks
- thermal or charging management
- a fully hardened remote control plane independent of Tailscale or localhost
  binding

## Operating Baseline

Use these rules as the minimum standard before leaving the machine unattended:

- keep the machine on stable AC power
- confirm `tailscaled` and SSH are enabled, not only active
- do not assume lid-close behavior is safe until you verify it
- keep important work inside `tmux` or saved to disk before walking away
- verify remote reachability before leaving home

## File Map

- `README.md`: repository entry point
- `documentation.md`: repository-level scope and file map
- `startup.md`: normal operator workflow
- `projects/remote-terminal/README.md`: remote-access setup
- `projects/server-mode/documentation.md`: server-mode usage and design

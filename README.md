# Remote-Terminal

Public documentation, templates, and scripts for reaching a home Linux machine
from a phone and leaving that machine in a safer unattended remote-access
state.

The repository is split into two related workspaces:

1. [Remote Terminal](projects/remote-terminal/README.md)
   Practical `Tailscale`/`SSH`/`tmux` guidance for establishing secure remote shell
   access without exposing SSH directly to the public internet.
2. [Server Mode](projects/server-mode/documentation.md)
   A reversible laptop workflow for ensuring Tailscale and SSH are running,
   applying a temporary logind suspend override, inspecting saved state, and
   restoring the machine later.

Portfolio case study: https://cristiancolacel.com/projects/remote-terminal

## Start Here

1. Read [projects/remote-terminal/README.md](projects/remote-terminal/README.md)
   for the connectivity setup.
2. Read [documentation.md](documentation.md) for the repository-level scope.
3. Read [startup.md](startup.md) for the normal server-mode operator flow.
4. Read [projects/server-mode/documentation.md](projects/server-mode/documentation.md)
   for server-mode usage and supporting utilities.

## What This Repo Is For

- documenting the architecture and tradeoffs
- keeping safe example configs and bootstrap scripts
- providing a reproducible starting point for personal remote access
- recording a conservative unattended-laptop workflow


## Structure

- `documentation.md`
- `startup.md`
- `projects/remote-terminal/`
- `projects/server-mode/`

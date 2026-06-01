# Server Mode

## Purpose

`server-mode` is a small reliability layer for a Linux laptop that is left at
home for remote access. The project is intentionally conservative: record the
current state, ensure the core remote-access services are up, apply a
reversible logind policy that reduces suspend risk, and make it easy to leave
that state again.

## Current Scripts

- [enter-server-mode.sh](enter-server-mode.sh): enter the mode
- [inspect-server-mode.sh](inspect-server-mode.sh): inspect the saved state
- [exit-server-mode.sh](exit-server-mode.sh): restore the saved service state
- [server-mode-ui.sh](server-mode-ui.sh): interactive menu wrapper
- [server-mode-status.sh](server-mode-status.sh): status snapshot in text or JSON
- [server-mode-dashboard.sh](server-mode-dashboard.sh): compact terminal dashboard
- [server-mode-web.py](server-mode-web.py): local browser dashboard
- [server-mode-web-start.sh](server-mode-web-start.sh): start the local web UI
- [server-mode-web-stop.sh](server-mode-web-stop.sh): stop the local web UI
- [server-mode-publish.sh](server-mode-publish.sh): publish the local web UI with Tailscale Serve
- [server-mode-unpublish.sh](server-mode-unpublish.sh): disable Tailscale Serve

## What Entering Server Mode Does

`enter-server-mode.sh` currently:

1. Detects whether AC power appears `online`, `offline`, or `unknown`.
2. Detects whether the system SSH service is `sshd` or `ssh`.
3. Records the current enabled and active state of `tailscaled` and SSH.
4. Records the invoking user, shell, and a best-effort history baseline.
5. Ensures `tailscaled` is enabled and started.
6. Ensures the detected SSH service is enabled and started.
7. Writes a dedicated logind drop-in at
   `/etc/systemd/logind.conf.d/remote-terminal-server-mode.conf`.
8. Sets `HandleLidSwitch=ignore`,
   `HandleLidSwitchExternalPower=ignore`, and `IdleAction=ignore`.
9. Restarts `systemd-logind` so the policy takes effect immediately.
10. Prints a summary with hostname, power state, service state, Tailscale IP,
    and current logind values.

Optional flags:

- `--require-ac`
- `--dry-run`
- `--skip-services`
- `--skip-logind-policy`

## What Inspecting Does

`inspect-server-mode.sh` reads the saved state file and prints:

- when server mode was entered
- how long it has been active
- the saved pre-enter service state
- the current live service state
- a best-effort command-history delta when the shell history file is known

It does not modify services or remove the state file.

## What Exiting Does

`exit-server-mode.sh`:

1. Loads the saved state file.
2. Restores `tailscaled` to its recorded pre-enter active and enabled state.
3. Restores the detected SSH service to its recorded pre-enter active and
   enabled state.
4. Restores or removes the managed logind drop-in, depending on what existed
   before enter.
5. Restarts `systemd-logind` so the restored policy takes effect immediately.
6. Removes the saved state file by default.

Useful options:

- `--dry-run`: print the actions without applying them
- `--keep-state`: restore services but keep the saved state file
- `--reboot`: restore state, then reboot the laptop
- `--poweroff`: restore state, then power off the laptop

## Interactive and Optional Interfaces

`server-mode-ui.sh` provides a simple `whiptail` interface for enter, inspect,
exit, reboot, and poweroff flows.

`server-mode-status.sh`, `server-mode-dashboard.sh`, and `server-mode-web.py`
are optional local monitoring interfaces built around the same saved state and
live service checks.

If you want phone access to the local browser UI through your tailnet, use the
manual publish helpers:

```bash
./server-mode-web-start.sh
./server-mode-publish.sh
./server-mode-unpublish.sh
./server-mode-web-stop.sh
```

## What This Project Does Not Do Yet

- tune Wi-Fi power saving
- stop desktop applications
- manage thermal or charging policy

Because of that, `server mode` covers service-state management plus a specific
reversible logind power-policy override. It is still not a full unattended-host
policy manager.

## Recommended Usage

Enter:

```bash
sudo ./enter-server-mode.sh --require-ac
```

Inspect:

```bash
sudo ./inspect-server-mode.sh
```

Exit:

```bash
sudo ./exit-server-mode.sh
```

Restart after exit:

```bash
sudo ./exit-server-mode.sh --reboot
```

Power off after exit:

```bash
sudo ./exit-server-mode.sh --poweroff
```

The managed logind policy applied on enter is:

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
IdleAction=ignore
```

That policy lives in `/etc/systemd/logind.conf.d/remote-terminal-server-mode.conf`
while server mode is active.

## Validation

The current workflow is behaving as intended when:

1. `tailscaled` is enabled and active after entering server mode.
2. SSH is enabled and active after entering server mode.
3. The machine has a reachable Tailscale address.
4. `loginctl show-logind` reports the temporary `ignore` values after enter.
5. `inspect-server-mode.sh` shows the expected saved state.
6. `exit-server-mode.sh` restores the saved service state and logind policy
   cleanly.

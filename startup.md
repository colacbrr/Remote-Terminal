# Startup Guide

This is the normal operator flow after the remote terminal setup already exists.

## One-Time Baseline

The machine should already have:

- Tailscale installed and authenticated
- SSH installed
- `tailscaled` enabled
- the correct SSH service enabled: `sshd` or `ssh`

## Normal Flow

1. Boot the laptop.
2. Confirm Tailscale and SSH came back.
3. Enter server mode before leaving the machine unattended.
4. Verify the laptop is still reachable.

## Verify After Boot

Run:

```bash
systemctl is-enabled tailscaled
systemctl is-active tailscaled
systemctl is-enabled sshd || systemctl is-enabled ssh
systemctl is-active sshd || systemctl is-active ssh
tailscale status
tailscale ip -4
```

## Enter Server Mode

```bash
cd /path/to/Remote-Terminal/projects/server-mode
sudo ./enter-server-mode.sh --require-ac
```

Or use the interactive wrapper:

```bash
cd /path/to/Remote-Terminal/projects/server-mode
./server-mode-ui.sh
```

Expected result:

- AC power is confirmed
- `tailscaled` is enabled and active
- SSH is enabled and active
- lid-close and idle suspend are temporarily overridden through logind
- a state file is written to `/var/lib/remote-terminal-server-mode/state.env`

## Inspect While Active

```bash
sudo ./inspect-server-mode.sh
```

Useful optional views:

```bash
./server-mode-status.sh
./server-mode-dashboard.sh --watch 5
python3 ./server-mode-web.py
```

For the browser UI, run `sudo python3 ./server-mode-web.py` if you want the
control buttons to work.

## Exit Server Mode

```bash
sudo ./exit-server-mode.sh
```

Useful options:

```bash
sudo ./exit-server-mode.sh --dry-run
sudo ./exit-server-mode.sh --keep-state
sudo ./exit-server-mode.sh --reboot
sudo ./exit-server-mode.sh --poweroff
```

## If Something Fails

If Tailscale is not connected:

```bash
sudo systemctl restart tailscaled
tailscale status
```

If SSH is not active:

```bash
sudo systemctl restart sshd
systemctl status sshd --no-pager
```

If your distro uses `ssh`, use that service name instead.

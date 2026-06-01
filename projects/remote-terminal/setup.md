# Remote Terminal Setup Checklist

This file is the practical setup order for the default working design in this
repo:

Phone -> Tailscale -> Linux Host -> SSH -> tmux

Use placeholders for your own environment. Do not store real private keys in
this repository.

## Personal Worksheet

Fill these in privately before changing anything:

- Linux distro: `<your distro>`
- Linux username: `<your user>`
- Linux host name: `<your host>`
- Router admin address: `<router IP>`
- Tailscale host IP or hostname: `<tailnet host>`
- Phone SSH client: `<client app>`

## Step 1: Install Required Packages

On Arch-based systems:

```bash
sudo pacman -Sy --needed openssh tmux ufw tailscale
```

On Ubuntu or Debian:

```bash
sudo apt update
sudo apt install -y openssh-server tmux ufw tailscale
```

Or use the bootstrap scripts in `scripts/`.

## Step 2: Enable SSH

Arch-based systems:

```bash
sudo systemctl enable --now sshd
sudo systemctl status sshd --no-pager
```

Ubuntu or Debian:

```bash
sudo systemctl enable --now ssh
sudo systemctl status ssh --no-pager
```

## Step 3: Bring Up Tailscale On The Host

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up
tailscale status
tailscale ip -4
```

Expected result:

- the host joins the tailnet
- a Tailscale IP is assigned
- the device shows as online

## Step 4: Bring Up Tailscale On The Phone

On the phone:

- install the Tailscale app
- sign in to the same account
- turn Tailscale on

Expected result:

- both phone and host appear in the same tailnet

## Step 5: Verify SSH Over Tailscale

Create an SSH client entry using:

- host: `<TAILSCALE_IP_OR_HOSTNAME>`
- username: `<SSH_USER>`
- port: `22`

Expected result:

- the client reaches the host
- SSH completes the handshake
- host key verification succeeds

If MagicDNS is unhealthy, use the raw Tailscale IP first.

## Step 6: Create A Dedicated SSH Key

On the host or the device where you manage keys:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/phone_remote_terminal -N ""
cat ~/.ssh/phone_remote_terminal.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Import the private key into the phone SSH client securely. Do not leave
temporary key copies lying around after import.

## Step 7: Test SSH Key Login

```bash
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no <SSH_USER>@<TAILSCALE_IP_OR_HOSTNAME>
```

Expected result:

- the phone or test client authenticates with the SSH key
- the shell opens successfully

## Step 8: Harden SSH After Key Auth Works

Review:

- [configs/ssh/sshd_config.hardening.example](configs/ssh/sshd_config.hardening.example)

Typical verification flow:

```bash
sudo sshd -t
sudo systemctl reload sshd
```

Do not disable password authentication until key-based login has already worked
from a separate fresh session.

## Step 9: Use tmux For Persistent Sessions

Start a session:

```bash
tmux
```

Detach:

```text
Ctrl+B, then D
```

Reattach:

```bash
tmux attach
```

## Optional Step: Native WireGuard

Only use the WireGuard path when your network actually supports inbound
reachability.

Reference files:

- [configs/wireguard/wg0.conf.example](configs/wireguard/wg0.conf.example)
- [documentation.md](documentation.md)

## Validation Checklist

- host is online in the tailnet
- phone is online in the same tailnet
- SSH key login works
- password auth is disabled only after verification
- `tmux` survives reconnects

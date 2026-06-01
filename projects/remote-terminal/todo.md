# Remote Terminal Todo

Use this as a reusable checklist when reproducing the setup.

## Immediate Tasks

1. Install SSH, `tmux`, firewall tooling, and Tailscale on the host.
2. Confirm the host appears online in the tailnet.
3. Confirm the phone appears online in the same tailnet.
4. Verify SSH over the Tailscale IP or hostname.
5. Create and import a dedicated SSH key for the phone client.
6. Confirm key-based login from a fresh session.
7. Apply SSH hardening only after that confirmation.
8. Start using `tmux` for reconnect-safe sessions.

## Useful Verification Commands

```bash
tailscale status
tailscale ip -4
systemctl status sshd --no-pager
```

```bash
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no <SSH_USER>@<TAILSCALE_IP_OR_HOSTNAME>
```

## Optional Follow-Up Tasks

1. Fix MagicDNS warnings if hostname resolution is inconsistent.
2. Add SSH host aliases in `~/.ssh/config`.
3. Add a dedicated server-mode script later.
4. Revisit native WireGuard only if the network supports it.

## Notes

- do not forward SSH port `22` directly to the public internet
- do not disable password auth until key auth is verified
- do not store VPN or SSH private keys in this repository

## Related Files

- [setup.md](setup.md)
- [documentation.md](documentation.md)
- [roadmap.md](roadmap.md)
- [configs/wireguard/wg0.conf.example](configs/wireguard/wg0.conf.example)
- [configs/ssh/sshd_config.hardening.example](configs/ssh/sshd_config.hardening.example)

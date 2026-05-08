# Secondary Tailscale instance for client users

## Overview

Runs a second `tailscaled` daemon alongside the personal one to connect
to a client's work tailnet. Uses userspace networking to avoid
TUN/iptables/routing conflicts with the primary tailscale.

All names are derived from the Linux username — nothing client-specific
is hardcoded. Client-specific config (tailnet, auth keys, hostnames)
belongs in `~/.clientrc`, never in this repo.

Key design decisions:
- `--tun=userspace-networking` avoids TUN/nftables conflicts with primary tailscale (TUN real causes iptables rule collision on `up`, breaks personal routing and kills SSH)
- `DevicePolicy=closed` in systemd prevents TPM contention with primary tailscaled (`/dev/tpmrm0`); state is saved unencrypted as a result
- `--accept-routes` is BLOCKED in the wrapper (imports subnet routes that overwrite personal tailscale routing, causes total loss of SSH access)
- Service/socket/wrapper names derived from `$USER` parameter
- Single instance per client user — connect/disconnect as needed

## Architecture

```
tailscaled (personal)             tailscaled-<user> (work)
├── socket: /run/tailscale        ├── socket: /run/tailscale-<user>.sock
├── port: 41641                   ├── port: 41642
├── tun: tailscale0               ├── tun: userspace-networking
├── state: /var/lib/tailscale     ├── state: /var/lib/tailscale-<user>
└── netfilter: on                 └── netfilter: n/a (userspace)
```

## Setup (one-time, as admin)

```bash
sudo ~/.dotfiles/linux/tailscale-client-setup.sh <user>
```

Creates: systemd service, wrapper script, sudoers rules.

From the Mac, after the workstation has this repo installed:

```bash
work tailscale-setup <user>
work vpn-doctor <user>
```

## Daily usage (as client user)

```bash
tailscale-<user> up --authkey=tskey-auth-...   # first time
tailscale-<user> status                         # check
tailscale-<user> down                           # disconnect
tailscale-<user> start                          # start daemon
tailscale-<user> stop                           # stop daemon
```

## Files created

| Path | Purpose |
|------|---------|
| `/etc/systemd/system/tailscaled-<user>.service` | systemd unit |
| `/usr/local/bin/tailscale-<user>` | wrapper script |
| `/etc/sudoers.d/tailscale-<user>` | passwordless sudo rules |
| `/var/lib/tailscale-<user>/` | state directory |
| `/run/tailscale-<user>.sock` | daemon socket |

## Client-specific config

Auth keys, tailnet names, and host aliases go in `~/.clientrc`:

```bash
# ~/.clientrc (per-user, NOT in the repo)
export TAILSCALE_AUTHKEY="tskey-auth-..."
alias vpn-up="tailscale-$USER up --authkey=\$TAILSCALE_AUTHKEY"
alias vpn-down="tailscale-$USER down"
alias vpn-status="tailscale-$USER status"
```

## Troubleshooting

### NEVER use --accept-routes
The wrapper blocks this flag. It imports subnet routes that overwrite
personal tailscale routing, causing total loss of SSH access.
Access work hosts directly by their Tailscale IPs (100.x.x.x).

### Personal tailscale lost connectivity
1. Connect via LAN: `ssh admin@<lan-ip>`
2. `sudo systemctl stop tailscaled-<user>`
3. `sudo systemctl restart tailscaled`
4. Verify: `tailscale status`

### Socket not found
The daemon isn't running: `tailscale-<user> start`

### Service won't start after reboot
Re-enable: `sudo systemctl enable --now tailscaled-<user>`

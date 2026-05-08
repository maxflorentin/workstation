# Pi Workstation (Legacy)

This document describes the earlier Raspberry Pi workstation model. The current
target is a Dell/headless Linux workstation; see [workstation.md](workstation.md).

Headless dev server for isolated freelance workspaces.
Client traffic stays on the server. Your Mac stays clean.

## Isolation model (multi-user)

**One Linux user on the Pi per client.**

```
/home/max/         admin user — dotfiles, VPN configs, compliance tooling
/home/<client1>/   client user — own dotfiles clone, venv, envy, work-tracker log
/home/<client2>/   ...
```

Per-user homes (`chmod 700`) give you OS-level aisolation between clients. `ps`, `find`, `rg` from one client's session cannot see another client's data. `work connect <client>` SSHes **as that client user** — the client name and the Linux user are the same.

Admin ops (`useradd`, VPN up/down, Wazuh config) still run as `max` via `sudo`.

## Components

| File | Runs on | Description |
|------|---------|-------------|
| `linux/bootstrap.sh` | Server | Installs the full stack (Docker, Node, Claude Code, Neovim, Starship, fastfetch, etc.) |
| `linux/work` | Mac | CLI to manage workspaces, VPNs, sessions, and monitoring |
| `linux/tmux-layout` | Server | Per-user tmux workspace layout (derives client from `$USER`) |
| `linux/tmux.conf` | Server | Minimal tmux theme with active-pane purple border |
| `linux/fastfetch.jsonc` | Server | `work status` dashboard config |
| `scripts/work-tracker` | Both | Time tracking (per-user log) |

## `work` CLI

```bash
work connect [client] [project]   # SSH as client + tmux (fuzzy project match)
work user-create <client>         # Create dedicated Linux user + dotfiles + envy + venv
work status                       # fastfetch-style Pi dashboard
work health                       # Quick health check with alerts
work watch [seconds]              # Live monitor (default: 30s)
work sync <client> [dir] [sub]    # Rsync local dir to client's home
work browse <client>              # Chrome routed via Pi network/VPN
work browse-stop [client]         # Stop SOCKS proxy
work vpn-up <client>              # Start client WireGuard VPN
work vpn-down <client>            # Stop client VPN
work ssh-keygen <client> [host]   # Generate ed25519 key in client's home
work destroy <client>             # userdel -r + cleanup SSH keys + VPN config
work report [--day|--week|--month|--cal|--prev|--all]
work tracker-status               # Active sessions (Mac + each client)
```

## Setup

1. Flash Raspberry Pi OS Lite (64-bit) with SSH enabled
2. `ssh-copy-id` your key to the server
3. Run `linux/bootstrap.sh` on the server
4. Add SSH config entry on your Mac

## Post-Bootstrap

### Home encryption (ecryptfs) — for compliance-heavy clients only

```bash
# Create temporary encryption user (sudoer)
sudo useradd -mb /home -s /bin/bash -G sudo encryption_user
sudo passwd encryption_user

# Log out, log in as encryption_user, then:
sudo ecryptfs-migrate-home -u <client>

# Log out, log in as <client>, verify files, then cleanup:
sudo userdel --remove encryption_user
sudo rm -rf /home/<client>.*
```

The bootstrap script automatically handles the SSH `authorized_keys` fix for ecryptfs (moves keys to `/etc/ssh/authorized_keys/%u` so SSH works before home is mounted).

Save the recovery key: `ecryptfs-unwrap-passphrase ~/.ecryptfs/wrapped-passphrase`

### DNS filtering (NextDNS via dnsmasq)

```bash
sudo apt install -y dnsmasq
sudo tee /etc/dnsmasq.d/nextdns.conf << EOF
no-resolv
bogus-priv
strict-order
server=45.90.28.0
server=45.90.30.0
add-cpe-id=YOUR_NEXTDNS_ID
EOF
sudo systemctl restart dnsmasq
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
```

### Compliance tools (per client)

Some clients require additional security software. These are NOT part of the standard bootstrap.

**Critical: scope Wazuh to a single client's home**, or it will see everything on the box:

```xml
<!-- /var/ossec/etc/ossec.conf -->
<syscheck>
  <directories check_all="yes" realtime="yes">/home/<client></directories>
</syscheck>
```

After editing: `sudo systemctl restart wazuh-agent`

```bash
# ClamAV (antivirus)
sudo apt install -y clamav clamav-daemon
sudo freshclam && sudo systemctl enable clamav-daemon

# Wazuh agent (SIEM) — follow client-provided installer
# Tailscale (VPN mesh) — follow client instructions for auth key
```

## Client Onboarding

```bash
# From Mac — creates Linux user, clones dotfiles, installs, sets up envy/venv/.clientrc:
work user-create <client>

# Generate an SSH key (for the client's GitHub/GitLab):
work ssh-keygen <client>

# Connect and customize:
work connect <client>
vim ~/.clientrc    # now lives in client's home, not under ~/clients/
```

Each client gets:
- Dedicated Linux user with home `chmod 700`
- Own dotfiles clone at `~/.dotfiles`
- Own Python venv at `~/.venv`
- Own envy context with age-encrypted secrets
- Own `.clientrc` (env vars + aliases)
- Own `~/.local/share/work-tracker/log.tsv` (isolated time tracking)
- Own cron for `work-tracker pulse`

## VS Code Remote

Install the "Remote - SSH" extension. Connect via `Cmd+Shift+P` > "Remote-SSH: Connect to Host" > `<client>@workstation`. The `<client>` prefix picks the right Linux user.

## Client VPNs

Each client can have its own WireGuard config at `/etc/wireguard/<client>.conf` (owned by root, managed by admin user).

`work vpn-up` checks for full-tunnel configs (`AllowedIPs = 0.0.0.0/0`) and warns before activation, since routing all traffic through the client VPN would kill your SSH session. Always use split tunneling — only route the client's internal subnets.

## Time tracking

Each client user runs its own `work-tracker pulse` cron every 5 min. `work report` from Mac iterates all client users on the Pi via SSH and merges their logs with the Mac-local log (which tracks Mac → Pi connection start/stop events).

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WORK_PI_HOST` | `workstation` | Server hostname or IP |
| `WORK_PI_USER` | `max` | Admin user on Pi |
| `WORK_DOTFILES_REPO` | `https://github.com/maxflorentin/dotfiles-mbairm4.git` | Repo cloned into new client homes |

## Remote Access

See [remote-access.md](remote-access.md) for the complete setup guide (Tailscale, WireGuard, SSH profiles, iPhone config).

## Development Workflow

See [dev-workflow.md](dev-workflow.md) for how to split work between Mac and Pi (VSCode Remote, Claude Code, Docker, iPhone access).

## Migration

The setup is portable. To move to a new machine:

**Automated (recommended):**

```bash
# On the new machine after Debian 12 minimal install:
bash migrate.sh --from workstation
```

See `linux/migrate.sh` — handles bootstrap, user creation with matching UIDs, rsync of homes/secrets/VPN configs, ecryptfs, Tailscale, and laptop server config (lid switch, console blanking).

**Manual:**

1. Run `linux/bootstrap.sh` on the new host
2. Recreate each client: `work user-create <client>`
3. Restore data: rsync each `/home/<client>/` from old host
4. Copy `~/.envy/` per client (if applicable)
5. Copy WireGuard configs from `/etc/wireguard/`
6. Update `WORK_PI_HOST` (env var or `~/.ssh/config`)

Everything else (`work` CLI, tmux layouts, aliases) works unchanged.

### Dell Latitude setup notes

If migrating to a laptop (Dell Latitude or similar) for use as a headless server:

- **BIOS (F2):** Power Management → AC Recovery → Last State (auto power-on after outage)
- **Wake on LAN:** Enable in BIOS (remote wake via Ethernet)
- **Lid switch:** `migrate.sh` configures systemd to ignore lid close
- **Battery:** acts as a built-in mini UPS for short power cuts
- **Ethernet:** prefer wired connection for server reliability

### USB pendrive prep (from Mac)

```bash
# Format USB
diskutil eraseDisk FAT32 MIGRATE /dev/diskN

# Copy migration script
cp ~/.dotfiles/linux/migrate.sh /Volumes/MIGRATE/

# Optional: offline dotfiles tarball
tar czf /Volumes/MIGRATE/dotfiles.tar.gz -C ~ .dotfiles/

# Copy Debian 12 ISO (download from debian.org)
cp ~/Downloads/debian-12-*-netinst.iso /Volumes/MIGRATE/
```

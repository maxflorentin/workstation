# Workstation

Headless Linux development workstation for isolated freelance/client work.

The current target is a Dell i5 class machine with 32GB RAM and local SSD
storage, running 24/7. The Raspberry Pi is no longer the primary development
host; it can be repurposed later for media or homelab services.

## Goals

- Keep the Mac clean: operator machine, browser/proxy launcher, SSH client.
- Keep the workstation always on: code, tmux, git, Docker, client isolation.
- Keep client state separated: one Linux user per client.
- Keep privilege centralized: only the `max` admin user should have sudo.
- Prefer Tailscale over raw WireGuard for remote access.
- Detect fragile state early with doctor/smoke checks.

## Architecture

```
Mac
  - terminal, browser, editor
  - Tailscale personal node
  - work/workstation CLIs
        |
        | SSH over Tailscale
        v
Linux workstation
  - admin user: max
  - client users: /home/<client>
  - tmux sessions per client/project
  - Docker workloads
  - personal tailscaled
  - optional secondary tailscaled-<client> instances
```

## Command Model

| Command | Scope | Purpose |
|---------|-------|---------|
| `./install` | local user | Dotfiles, symlinks, PATH, scripts |
| `workstation ci` | repo-local | Run lint and smoke checks |
| `workstation smoke` | repo-local | Fast syntax/help checks |
| `workstation lint` | repo-local | Shellcheck, whitespace, and sanitization checks |
| `workstation doctor` | local host | Validate prerequisites and links |
| `workstation bootstrap` | Linux server | Install workstation base packages |
| `work doctor [client]` | Mac -> server | General workstation/client health checks |
| `work compliance-doctor <client>` | Mac -> server | Check optional per-client compliance profile |
| `work backup-doctor` | Mac -> server | Check backup/recovery readiness without copying data |
| `work connect <client>` | Mac -> server | SSH into client tmux workspace |
| `work connect --browse <client>` | Mac -> server | SSH into client workspace and open isolated browser |
| `WORK_CONNECT_BROWSE=1 work connect <client>` | Mac -> server | SSH into client workspace and open isolated browser |
| `work tailscale-setup <client>` | Mac -> server | Install secondary Tailscale daemon for a client |
| `work vpn-doctor [client]` | Mac -> server | Validate personal and secondary Tailscale |
| `envy-doctor [context]` | local user | Validate secret-store health without printing secrets |

`work compliance-doctor <client>` is not a workstation-wide baseline. Use it
only for clients that explicitly require the compliance profile. It checks the
endpoint agent, Wazuh syscheck scope when readable, DNS filtering, antivirus,
and encryption.

## Browser Companion

`work browse <client>` starts a local SOCKS proxy to the workstation and opens
an isolated Chrome profile for that client.

For one-off sessions:

```bash
work connect --browse <client>
```

For a shell/profile default:

```bash
WORK_CONNECT_BROWSE=1 work connect <client>
```

Plain `work connect <client>` intentionally does not open a browser.

Useful companion commands:

```bash
work browse --status <client>
work browse-stop <client>
```

For DNS filtering, the doctor accepts either a `systemd-resolved`
NextDNS-over-TLS configuration or a `dnsmasq` NextDNS configuration. Real
profile IDs belong only in host-local config files and must not be committed.

For Wazuh, syscheck must be scoped to that client home, for example
`/home/<client>`. It must not monitor `/home`, `/home/max`, `/etc`, `/usr`,
`/bin`, `/sbin`, or `/boot` for a client-specific compliance profile.

This is a hard isolation rule. Compliance tooling must not undo the repository's
core model of one client per Linux user. If `work compliance-doctor <client>`
cannot read the Wazuh configuration, run it on the workstation with sudo:

```bash
sudo ~/.local/bin/work compliance-doctor <client>
```

## Configuration

Preferred environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSTATION_HOST` | `workstation` | Server hostname or Tailscale MagicDNS name |
| `WORKSTATION_USER` | `max` | Admin user on the workstation |
| `WORKSTATION_DOTFILES_REPO` | current GitHub repo | Repo cloned into new client users |

Legacy names still work while the repo migrates:
`WORK_PI_HOST`, `WORK_PI_USER`, `WORK_DOTFILES_REPO`.

## Repository Identity

The repo may keep the historical local path `~/.dotfiles` while the public
GitHub repo name evolves. Treat `~/.dotfiles` as an install location, not as the
product name.

Canonical repo name:

```text
git@github.com:maxflorentin/workstation.git
https://github.com/maxflorentin/workstation.git
```

When renaming the GitHub repo, keep the default repo URL aligned in:

- `linux/work`
- `linux/bootstrap.sh`

Existing clones can continue to work through GitHub redirects, but new client
users should clone from the canonical repo URL through
`WORKSTATION_DOTFILES_REPO`.

## VPN/Tailscale Model

The personal Tailscale daemon is the control plane for reaching the workstation.
Client-specific Tailscale access uses a secondary daemon configured with
userspace networking:

- primary: `tailscaled`, socket `/run/tailscale/tailscaled.sock`
- client: `tailscaled-<client>`, socket `/run/tailscale-<client>.sock`
- client wrapper: `/usr/local/bin/tailscale-<client>`
- `--accept-routes` is blocked for secondary instances

Run:

```bash
work doctor
work vpn-doctor
work doctor <client>
work vpn-doctor <client>
```

`work vpn-doctor` checks the Mac and workstation personal Tailscale path.
`work vpn-doctor <client>` also checks the client's secondary daemon, wrapper,
socket, userspace networking, blocked `--accept-routes`, and client-user status.

## Reliability Priorities

- SSH reachable over Tailscale.
- `tailscaled` active after reboot.
- `max` remains the only sudo-capable operator account.
- Disk/RAM/temperature visible through health checks.
- Work tracker running predictably.
- Docker available but treated as privileged access.
- Backups and recovery runbooks documented before adding more services.

## Privilege Model

The workstation is intentionally not a shared sudo environment.

- `max` is the admin/operator account and the only user expected to have sudo.
- Client users should not have sudo.
- System packages, shared CLIs, Docker, Tailscale, and services are installed or
  maintained from `max`.
- Client users may consume shared tooling, but their client-specific state should
  stay in `/home/<client>`.
- Passwordless sudo is optional. Doctors avoid prompting for passwords; if
  `sudo -n` is unavailable, privileged checks are skipped or reported as limited.

Docker group membership is still treated as privileged host access. A client in
the `docker` group is effectively trusted with broad control over the host.
New client users are not added to `docker` by default. Use
`WORK_CLIENT_DOCKER=1 work user-create <client>` only when that tradeoff is
intentional.

## Workstation Packages

The Linux bootstrap installs operational validation tools such as `shellcheck`
and `lm-sensors`. Existing hosts can be brought in line manually:

```bash
sudo apt-get update
sudo apt-get install -y shellcheck lm-sensors
sudo sensors-detect
```

`sensors-detect` is interactive and should be run as `max`.

For ClamAV setup, use `work clamav-setup` and then verify with
`work compliance-doctor <client>`.

## Migration Notes

The `linux/` directory remains for Linux workstation scripts and compatibility
entrypoints. New orchestration entrypoints should live under `workstation/`
where practical; keep compatibility wrappers in place until installed commands
and docs have moved.

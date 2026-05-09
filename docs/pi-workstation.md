# Pi Workstation (Legacy)

This document is historical. The Raspberry Pi was the first always-on
development host, but it is no longer the primary workstation target.

Current source of truth:

- [Workstation](workstation.md) - Dell/headless Linux workstation architecture
- [Workstation Migration](workstation-migration.md) - applying the foundation to
  the current host
- [Secondary Tailscale](tailscale-client.md) - client tailnet isolation
- [Reliability](reliability.md) - health, backup, and recovery runbooks

## What This Used To Be

The original model was a Raspberry Pi acting as a headless dev server:

- one Linux user per client;
- SSH and tmux for remote work;
- per-client homes with `chmod 700`;
- optional client VPNs;
- local Mac kept mostly clean.

That model proved useful, but the Pi became resource-constrained once Docker and
multiple containers entered the workflow.

## Why It Changed

The current workstation target is a Dell/Linux host with more CPU, memory, and
storage. The architecture kept the useful pieces from the Pi model while moving
operational work to a more reliable 24/7 machine:

- `max` is the only sudo-capable operator account;
- client users remain isolated under `/home/<client>`;
- Tailscale is preferred over raw WireGuard;
- `workstation ci`, `work doctor`, `work vpn-doctor`, and
  `work compliance-doctor <client>` validate fragile state;
- compliance tooling is per-client only and must not become a global scan of
  all homes.

## What Still Applies

These ideas survived the migration:

- one Linux user per client;
- tmux sessions per client/project;
- isolated browser profiles launched from the Mac through `work browse`;
- optional secondary Tailscale daemon per client;
- encrypted secrets through Envy;
- configuration-only backups before broader data-backup work.

Use the current commands from [workstation.md](workstation.md), especially:

```bash
workstation ci
workstation doctor
work doctor [client]
work vpn-doctor [client]
work connect --browse <client>
sudo ~/.local/bin/work compliance-doctor <client>
```

## Future Use For The Pi

The Pi is no longer part of the core development path. It can be repurposed
later for media, homelab, or auxiliary services, but that should be planned as a
separate feature so it does not reintroduce workstation/client coupling.

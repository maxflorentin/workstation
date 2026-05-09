# Reliability And Recovery

This workstation is expected to run 24/7. Reliability work should preserve the
same isolation rules as the rest of the repo:

- `max` is the operator account.
- client users do not get sudo.
- client-specific compliance tooling stays scoped to that client.
- private names, IPs, IDs, and secrets stay out of git.

## Health Checks

From the Mac:

```bash
work doctor
work vpn-doctor
work backup-doctor
```

On the workstation:

```bash
workstation doctor
envy-doctor
```

For clients that require a compliance profile:

```bash
sudo ~/.local/bin/work compliance-doctor <client>
```

## Backup Readiness

`work backup-doctor` is non-destructive. It checks that the important state is
present and tells you when privileged verification was skipped.

For full checks on the workstation:

```bash
sudo ~/.local/bin/work backup-doctor
```

Optional target check:

```bash
WORK_BACKUP_TARGET=/path/to/backup-root work backup-doctor
```

## What Needs Backup

Back up these categories. Do not commit their contents to this repo.

| Category | Examples |
|----------|----------|
| Admin home | `/home/max`, except caches/build artifacts |
| Client homes | `/home/<client>` or encrypted backing stores |
| Encrypted homes | `/home/.ecryptfs/<client>` |
| ecryptfs config | `/etc/ecryptfs`, root-only |
| SSH auth | `/etc/ssh/authorized_keys`, selected SSH config |
| Service config | selected `/etc/systemd/system/*.service` |
| Secondary Tailscale | `tailscaled-<client>` units and wrappers |
| Compliance config | selected endpoint-agent config, scoped per client |
| Dotfiles repo | `~/.dotfiles` or Git remote |

Tailscale machine state can often be re-authenticated, but secondary client
daemon units and wrapper scripts should be recoverable.

## Restore Runbook

High-level restore flow:

1. Install Debian on the replacement host.
2. Restore SSH access for `max`.
3. Clone this repo and run `./install`.
4. Run `workstation bootstrap` if the base packages are missing.
5. Restore client users with matching names and homes.
6. Restore encrypted homes and required root-only ecryptfs config.
7. Restore selected systemd units and SSH authorized keys.
8. Re-authenticate Tailscale if needed.
9. Run `workstation doctor`, `work doctor`, and `work backup-doctor`.
10. For each compliance-profile client, run `sudo ~/.local/bin/work compliance-doctor <client>`.

Do not restore compliance tooling globally unless it is explicitly required for
that client and scoped to that client.

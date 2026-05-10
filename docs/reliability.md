# Reliability And Recovery

This workstation is expected to run 24/7. Reliability work should preserve the
same isolation rules as the rest of the repo:

- `max` is the operator account.
- client users do not get sudo.
- client-specific compliance tooling stays scoped to that client.
- private names, IPs, IDs, and secrets stay out of git.

## Health Checks

Current hardware baseline: Dell i5 class workstation, 32GB RAM, local SSD. The
resource doctors use percentage-based thresholds so they remain useful after
RAM/storage upgrades.

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

When `WORK_BACKUP_TARGET` is set, the doctor checks the expected private backup
repo structure: `README.restore.md`, `MANIFEST.tsv`, `clients/`, and
`workstation/`.

## Encrypted Config Backup

`work config-backup` creates an encrypted, config-only snapshot for one client.
Run it on the workstation so root-owned config never leaves the host as
plaintext.

```bash
sudo ~/.local/bin/work config-backup <client> /path/to/private-config-backup 'age1...'
```

Before writing encrypted files, validate the context with:

```bash
sudo ~/.local/bin/work config-backup --dry-run <client> /path/to/private-config-backup 'age1...'
```

For SSH recipients, quote the complete public key:

```bash
sudo ~/.local/bin/work config-backup <client> /path/to/private-config-backup 'ssh-ed25519 AAAA...'
```

The command refuses to write into this sanitized repo or into the client home.
It writes encrypted `.age` files under `clients/<client>/` and `workstation/`,
plus a small restore README in the private destination.
It also writes a plaintext `MANIFEST.tsv` with generated file names, statuses,
and labels. The manifest must not contain secrets; it is intended for quick
audits before committing the encrypted backup repo.

Expected inputs:

- `<client>` is the Linux client user.
- `<dest-dir>` is a separate private repo or private working tree.
- `<age-recipient>` is a public age or SSH recipient, not a private key.

## Config Backup Strategy

Current direction: back up **configuration only**, not client data.

Use a private repository with encrypted files for small restore-critical config:

```text
private-config-backup/
  README.restore.md
  MANIFEST.tsv
  clients/
    <client>/
      clientrc.age
      dns-filtering.age
      wazuh-scope.age
      tailscale-wrapper.age
      tailscale-unit.age
      compliance-latest.age
  workstation/
    ssh-authorized-keys.age
    systemd-client-units.age
```

Rules:

- encrypt files before committing them;
- do not commit plaintext client config;
- do not store encryption keys in the same repo;
- keep this public/sanitized repo free of client names and real infrastructure
  values;
- prefer client-owned private repos when ownership/compliance requires it.

`age` is the preferred encryption tool because the repo already uses it through
Envy. Restic/SSD data backups are a separate spike and are not part of this
phase.

## What Needs Backup

For the current config-only phase, back up restore-critical config. Do not
commit contents to this repo.

| Category | Examples |
|----------|----------|
| Client shell config | `/home/<client>/.clientrc` |
| ecryptfs config | `/etc/ecryptfs`, root-only |
| SSH auth | `/etc/ssh/authorized_keys`, selected SSH config |
| Service config | selected `/etc/systemd/system/*.service` |
| Secondary Tailscale | `tailscaled-<client>` units and wrappers |
| Compliance config | selected endpoint-agent config, scoped per client |
| Dotfiles repo | `~/.dotfiles` or Git remote |

Do not back up client data in this phase. If data backups are needed later,
evaluate Restic/Borg/SSD/offsite separately.

Tailscale machine state can often be re-authenticated, but secondary client
daemon units and wrapper scripts should be recoverable as config.

## Restore Runbook

High-level restore flow:

1. Install Debian on the replacement host.
2. Restore SSH access for `max`.
3. Clone this repo and run `./install`.
4. Run `workstation bootstrap` if the base packages are missing.
5. Restore client users with matching names.
6. Restore selected config from the encrypted private config backup repo.
7. Restore selected systemd units and SSH authorized keys.
8. Re-authenticate Tailscale if needed.
9. Run `workstation doctor`, `work doctor`, and `work backup-doctor`.
10. For each compliance-profile client, run `sudo ~/.local/bin/work compliance-doctor <client>`.

Do not restore compliance tooling globally unless it is explicitly required for
that client and scoped to that client.

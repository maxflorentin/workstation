# Spikes

Ideas intentionally not implemented yet.

## Restic / External SSD Data Backups

Status: deferred.

Restic is a good candidate for encrypted, deduplicated data backups, especially
to an external SSD or remote backend. For now, this repo is focusing on
configuration backups only.

Open questions:

- whether backups should be local-only, offsite, or both;
- whether the backup target is an external SSD, SFTP, S3-compatible storage, or
  client-owned storage;
- whether to back up encrypted ecryptfs backing stores or mounted plaintext
  homes;
- how backup credentials are stored and rotated;
- whether backup jobs run as `max`, root, or a restricted backup user.

Do not implement data backups until the restore model and ownership boundaries
are explicit.

## Connect Browser Companion

Status: partially implemented.

Desired workflow:

```bash
work connect <client>
```

can start the same isolated browser/proxy setup as:

```bash
work browse <client>
```

Current opt-in:

```bash
WORK_CONNECT_BROWSE=1 work connect <client>
```

Design notes:

- Keep this opt-in so a plain SSH/tmux connection does not unexpectedly open
  Chrome.
- Keep `work browse <client>` and `work browse-stop <client>` as explicit
  commands.
- Reuse the existing per-client SOCKS proxy and Chrome profile naming.
- Later, consider a CLI flag such as `work connect --browse <client>` if the
  command parser is cleaned up.

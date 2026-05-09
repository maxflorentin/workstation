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

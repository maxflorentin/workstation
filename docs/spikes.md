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

## Client Onboarding Skill / Agent

Status: backlog.

Create a repo-local skill or scripted assistant workflow for onboarding a new
client without leaking client names, brands, credentials, or network details
into git.

The workflow should guide or automate:

- client name validation and Linux user creation;
- sudo/docker decision recording;
- secondary Tailscale decision and setup;
- optional compliance profile setup and `compliance-doctor`;
- Envy context creation without printing secrets;
- SSH key generation and host-local SSH config notes;
- browser companion preference;
- config-only backup enrollment;
- final validation with `work doctor <client>`, `work vpn-doctor <client>`, and
  relevant compliance checks.

Open questions:

- whether this should be a Codex/Claude skill, a `work onboard <client>` command,
  or both;
- how much should be automated versus checklist-driven;
- where non-committable client notes should live;
- how to produce a sanitized onboarding summary for future audits.

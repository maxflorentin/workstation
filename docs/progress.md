# Progress

Current estimate: about 85% through the workstation foundation phase.

This is not a product roadmap. It is a working checkpoint for the migration
from personal dotfiles to a reliable, sanitized workstation repo.

## Done

- Repo identity moved to `workstation`.
- Raspberry Pi notes archived as legacy.
- Dell/Linux workstation documented as the primary 24/7 host.
- `workstation ci` runs lint and smoke checks.
- `work doctor` validates workstation and optional client state.
- Client model documented as one Linux user per client.
- Client users are not expected to have sudo.
- `.clientrc` template, init, doctor, profile, and client listing exist.
- `work connect --browse <client>` opens the browser companion.
- Personal and secondary Tailscale are validated through `work vpn-doctor`.
- Secondary Tailscale setup blocks route imports that can break personal access.
- Optional compliance checks are scoped to one client home.
- Wazuh syscheck scope is validated when compliance is enabled.
- ClamAV setup and compliance validation exist.
- Config-only encrypted backup tooling exists.
- Config-only backups include manifest checksums and schema validation.
- Backups are explicitly separated from data-backup spikes.
- Legacy WireGuard paths are hidden under `work legacy`.
- Legacy docs and one-off helper scripts are archived under `docs/legacy/` and
  `scripts/legacy/` instead of being deleted.
- Old experimental assistant commands were removed.
- Homebrew sync is profile-based and non-magical by default.
- Mac package baselines are split between personal, corporate, and workstation
  operator profiles.
- Sudo-dependent commands avoid password prompts in non-interactive flows.
- Sudo-limited paths are covered for onboarding, tracker repair/doctor,
  setup, legacy VPN, and destructive commands.
- Sanitization rules are documented and checked.
- Work-tracker has explicit doctor and per-client/all-client repair commands.
- `work onboard <client>` covers tracker repair, backup readiness, compliance
  boundaries, and restore drills.

## Remaining

- Exercise `work config-backup` against a real private backup repo and perform a
  restore drill.
- Decide whether the client onboarding flow should stay checklist-driven or
  become a repo-local skill.
- Verify work-tracker behavior after reconnects and reboots on the real host.
- Add deeper backup tests around restore metadata once a private backup target
  exists.
- Keep cleaning obsolete compatibility paths as real usage confirms they are no
  longer needed.

## Next Good Steps

1. Run a config-only backup spike in a private repo.
2. Run `work tracker-doctor` and repair clients with
   `work tracker-repair --all` or `work tracker-repair <client>`.
3. Decide whether onboarding remains checklist-driven or becomes a repo-local
   skill.
4. Add restore-oriented backup tests after the private backup repo shape is
   exercised once.

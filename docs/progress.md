# Progress

Current estimate: about 70% through the workstation foundation phase.

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
- Backups are explicitly separated from data-backup spikes.
- Legacy WireGuard paths are hidden under `work legacy`.
- Old experimental assistant commands were removed.
- Homebrew sync is explicit and non-magical by default.
- Sudo-dependent commands avoid password prompts in non-interactive flows.
- Sanitization rules are documented and checked.
- Work-tracker has explicit doctor and per-client/all-client repair commands.

## Remaining

- Exercise `work config-backup` against a real private backup repo and perform a
  restore drill.
- Decide whether the client onboarding flow should stay checklist-driven or
  become a repo-local skill.
- Improve `work onboard <client>` into a more complete guided flow.
- Verify work-tracker behavior after reconnects and reboots.
- Add focused tests for backup, onboarding, and sudo-limited behavior.
- Document the Mac package split between personal, workstation, and
  client-specific tooling.
- Keep cleaning obsolete compatibility paths as real usage confirms they are no
  longer needed.

## Next Good Steps

1. Run a config-only backup spike in a private repo.
2. Run `work tracker-doctor` and repair clients with
   `work tracker-repair --all` or `work tracker-repair <client>`.
3. Turn the onboarding checklist into either a CLI wizard or a repo-local skill.
4. Add tests around the sudo-limited flows that were recently hardened.

# Workstation Foundation Migration

Checklist for applying the `workstation-foundation` branch to the Linux
workstation.

## Preflight From Mac

```bash
git status --short
./tests/smoke.sh
workstation doctor
work doctor
work vpn-doctor
```

Expected local-only warnings are acceptable on the Mac:

- `tmux` missing
- `docker` missing
- `fastfetch` missing
- `shellcheck` missing
- `systemctl` missing

## Apply On Workstation

```bash
ssh workstation
cd ~/.dotfiles
git fetch origin
git switch workstation-foundation
./install
```

If the branch is not pushed yet, push it from the Mac first:

```bash
git push -u origin workstation-foundation
```

## Bring Packages In Line

```bash
sudo apt-get update
sudo apt-get install -y shellcheck lm-sensors
sudo sensors-detect
```

`sensors-detect` is interactive. Accept safe defaults unless there is a reason
to override them.

## Validate

On the workstation:

```bash
workstation doctor
envy-doctor
```

From the Mac:

```bash
work doctor
work vpn-doctor
```

For each client user:

```bash
work doctor <client>
work compliance-doctor <client>
work vpn-doctor <client>
```

## Client Decisions

### Docker Group

Client users should not be in the `docker` group by default. Docker group
membership is privileged host access.

Remove it when not intentionally needed:

```bash
sudo gpasswd -d <client> docker
```

For future users, Docker is opt-in:

```bash
WORK_CLIENT_DOCKER=1 work user-create <client>
```

### Secondary Tailscale

If a client needs access to a separate client tailnet:

```bash
work tailscale-setup <client>
work vpn-doctor <client>
```

If the client does not need a separate tailnet, `work vpn-doctor <client>` is
expected to report that the secondary instance is missing.

## Done Criteria

- `workstation doctor` passes on the workstation.
- `work doctor` passes from the Mac.
- `work vpn-doctor` passes from the Mac.
- Each client has an explicit decision for Docker group membership.
- Each client has an explicit decision for secondary Tailscale.
- Compliance-sensitive clients pass `work compliance-doctor <client>`.

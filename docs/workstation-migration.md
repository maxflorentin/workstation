# Workstation Foundation Migration

Checklist for applying the `workstation-foundation` branch to the Linux
workstation.

## Preflight From Mac

```bash
git status --short
workstation ci
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

If `shellcheck` or `rg` is not installed locally, run `workstation ci` on the
Linux workstation or rely on CI for that check.

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

For compliance-sensitive clients, initialize ClamAV with `work clamav-setup`.

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
work vpn-doctor <client>
```

Only for clients that explicitly require the compliance profile:

```bash
work compliance-doctor <client>
```

If the doctor cannot verify Wazuh scope because `/var/ossec/etc/ossec.conf` is
not readable, run it on the workstation with sudo:

```bash
sudo ~/.local/bin/work compliance-doctor <client>
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
- Clients that explicitly require the compliance profile pass
  `work compliance-doctor <client>`.
- Wazuh syscheck is scoped to `/home/<client>` and does not monitor global paths
  or other homes.
- DNS filtering config may use `systemd-resolved` or `dnsmasq`; real NextDNS
  profile IDs stay in host-local files only.

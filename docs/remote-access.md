# Remote Access

How to reach the headless Linux workstation from the Mac, phone, or another
trusted device.

Tailscale is the default remote-access path. The workstation may sit behind one
or more NAT layers, so inbound port forwarding should be treated as an
exception rather than the normal setup.

## Network Model

```text
Mac / phone / trusted device
  - personal Tailscale node
  - SSH client
        |
        | SSH over Tailscale
        v
Linux workstation
  - personal tailscaled
  - admin user: max
  - client users: /home/<client>
  - optional secondary tailscaled-<client> daemons
```

Keep local ISP names, router models, LAN IPs, and tailnet IPs out of this repo.
Those details belong in host-local notes or private encrypted config backups.

## Tailscale

Install and authenticate Tailscale on the workstation:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Verify on the workstation:

```bash
tailscale status
tailscale ip -4
systemctl is-active tailscaled
```

On the Mac, install Tailscale from the app or Homebrew, log into the same
personal tailnet, and verify:

```bash
tailscale status
tailscale ping workstation
ssh workstation
```

On iPhone or another mobile device, install Tailscale, log into the same
personal tailnet, enable the VPN toggle, and connect with an SSH app.

## SSH Profiles

Use MagicDNS or a host-local Tailscale IP in `~/.ssh/config`. Keep real IPs out
of git.

```sshconfig
Host workstation
    HostName workstation
    User max
```

Define one explicit host-local entry per client. Avoid committing real client
names to this repo.

```sshconfig
Host ws-<client>
    HostName workstation
    User <client>
```

For encrypted-home clients, first login may require password authentication so
the home can mount:

```sshconfig
Host ws-<client>
    HostName workstation
    User <client>
    PreferredAuthentications password
    PubkeyAuthentication no
```

The matching server-side SSH configuration lives on the workstation, not in this
repo.

## Verification

Run these after setup or while troubleshooting:

```bash
work doctor
work vpn-doctor
work doctor <client>
work vpn-doctor <client>
```

Direct checks:

```bash
tailscale status
tailscale ping workstation
ssh workstation
ssh <client>@workstation
```

For client-specific tailnets, use:

```bash
work tailscale-setup <client>
work vpn-doctor <client>
```

The secondary Tailscale daemon must use userspace networking and must not accept
routes. See [tailscale-client.md](tailscale-client.md).

## Troubleshooting

If the workstation is not reachable:

1. Check the workstation is powered on and reachable on the local network.
2. Check `tailscaled` is active on the workstation.
3. Check the Mac or phone is logged into the personal tailnet.
4. Run `tailscale status` on both sides.
5. Run `tailscale ping workstation` from the client device.
6. Use LAN SSH only as a temporary local fallback.

If a mobile device appears duplicated or stale in Tailscale, remove the stale
node from the Tailscale admin console or fully reinstall the mobile app, then
authenticate again.

## WireGuard

Raw WireGuard is no longer the primary remote-access model for this repo.

Use it only for a deliberate self-hosted VPN setup with a separate runbook.
Do not commit public IPs, router details, forwarded ports, or private keys.

For client-specific network access, prefer the secondary Tailscale model
documented in [tailscale-client.md](tailscale-client.md).

## Hardware Migration

When replacing the workstation:

1. Install Tailscale on the new machine.
2. Authenticate it into the personal tailnet.
3. Update host-local SSH config if MagicDNS is not enough.
4. Run `workstation doctor`, `work doctor`, and `work vpn-doctor`.
5. Remove or disable the old tailnet node when the migration is complete.

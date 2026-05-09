# Client Boundaries

This repo defines the workstation model and reusable tooling. Real client
identity, credentials, network details, and compliance evidence stay outside
git.

## Repo-Owned

Safe to commit here:

- generic scripts and doctors;
- sanitized docs with `<client>` placeholders;
- reusable templates such as `templates/clientrc.example`;
- tests that validate the generic behavior;
- runbooks that describe decisions without naming real clients.

## Host-Local

Keep these on the workstation or in a separate encrypted private backup:

- `/home/<client>/.clientrc`;
- `/home/<client>/.ssh`;
- `/home/<client>/.config`;
- endpoint-agent config and compliance evidence;
- secondary Tailscale auth state, tailnet names, and auth notes;
- DNS filtering profile IDs and provider-specific config;
- encrypted-home passphrase material under `/etc/ecryptfs`.

## Mac-Local

The Mac can keep operator conveniences:

- Homebrew state in `macos/Brewfile`;
- browser profile launchers and SOCKS proxy state;
- SSH client config using placeholders in docs and real aliases locally.

Do not copy real client SSH aliases, hostnames, proxy URLs, or browser profile
paths into this repo.

## Workstation-Local

The Dell owns shared host services and tools:

- packages installed by `workstation bootstrap`;
- shared CLIs under `max`;
- Docker and system services;
- personal Tailscale for reaching the workstation;
- optional secondary Tailscale daemons per client.

Client-specific state should still live under `/home/<client>` or root-owned
system config that is explicitly scoped to that client.

## Client Template

Start from:

```bash
work clientrc-init <client>
work clientrc-doctor <client>
```

Then edit the file on the workstation with real values. Never commit the
result. The doctor checks metadata and expected keys without printing values.

## Validation

For generic checks:

```bash
workstation ci
work doctor <client>
work clientrc-doctor <client>
work vpn-doctor <client>
```

For clients that explicitly require the compliance profile:

```bash
sudo ~/.local/bin/work compliance-doctor <client>
```

Compliance checks must stay scoped to the requested client. A client-specific
Wazuh/syscheck profile must include `/home/<client>` and must not scan global
paths such as `/home`, `/home/max`, `/etc`, `/usr`, `/bin`, `/sbin`, or `/boot`.

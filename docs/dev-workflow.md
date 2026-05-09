# Development Workflow

How to split work between the Mac, the headless Linux workstation, and mobile
access without leaking client state across users.

## Architecture

```text
Mac
  - terminal, browser, editor
  - personal Tailscale node
  - local `work` launcher
        |
        | SSH over Tailscale
        v
Linux workstation
  - admin user: max
  - client users: /home/<client>
  - tmux sessions
  - git, Docker, language runtimes
  - personal tailscaled
  - optional secondary tailscaled-<client>
        ^
        |
        | SSH over Tailscale
Phone / tablet
  - emergency terminal access
```

The Mac is the operator machine. The workstation owns long-running state,
client separation, Docker workloads, and tmux sessions. Mobile access is for
small interventions and status checks, not deep editing.

## Daily Flow

Start a client workspace:

```bash
work connect <client>
```

Start a client workspace and browser companion:

```bash
work connect --browse <client>
```

Or make browser launch the default for a shell/profile:

```bash
WORK_CONNECT_BROWSE=1 work connect <client>
```

Inside the workstation session, keep work in tmux. SSH drops should not lose the
active editor, shell state, or long-running command output.

## Browser Companion

`work browse <client>` opens an isolated Chrome profile on the Mac while routing
browser traffic through a SOCKS proxy to the workstation.

Useful commands:

```bash
work browse <client>
work browse --status <client>
work browse-stop <client>
```

This is useful for client portals, web apps, and tools that need to appear from
the workstation network context. It does not magically isolate every Mac app.
For apps that do not support SOCKS/proxy configuration cleanly, prefer browser
based access or run the tool inside the client user on the workstation.

## Editing

Preferred options:

- terminal editor inside `work connect <client>`;
- local Mac editor for repo-local changes in this repo;
- Remote SSH editor only when the client workflow really benefits from it.

For Remote SSH, define host-local entries outside this repo:

```sshconfig
Host ws-<client>
    HostName workstation
    User <client>
```

Encrypted-home clients may need one password login first so ecryptfs can mount.
After the home is mounted, key-based auth can work through server-side
authorized keys.

Keep editor caches, real hostnames, IPs, and client-specific SSH aliases out of
git.

## Docker

Default: run project containers on the workstation under the relevant client
user, unless the project explicitly needs Mac-only tooling.

Why:

- the workstation is always on;
- tmux sessions survive Mac sleep/reboot;
- client project state stays under `/home/<client>`;
- Docker access is treated as privileged host access and should be intentional.

Do not add client users to the `docker` group by default. Use
`WORK_CLIENT_DOCKER=1 work user-create <client>` only when the privilege tradeoff
is explicit.

Mac Docker remains useful for local experiments, UI-heavy workflows, or projects
that should not touch the workstation. Treat that as a per-project decision.

## AI Coding Tools

Run CLI coding tools either on the Mac for local repo work or inside tmux on the
workstation for client/project work.

On the workstation:

```bash
work connect <client>
tmux attach
```

Keep credentials in the appropriate user context. Shared or personal secrets
should not be copied into client homes unless the client workflow explicitly
requires them.

For headless auth flows, prefer documented CLI/API-token auth where available.
If an auth file must be copied from the Mac, copy it only into the intended user
home and include it in the config-backup review before relying on it.

## Mobile Access

Mobile is for quick fixes, status checks, and recovering a session:

1. Enable Tailscale on the device.
2. SSH to `workstation` or `<client>@workstation`.
3. Attach tmux.

```bash
ssh workstation
tmux attach
```

For client work:

```bash
ssh <client>@workstation
tmux attach
```

## Validation

Before starting a focused work session:

```bash
work doctor
work vpn-doctor
```

For a specific client:

```bash
work doctor <client>
work vpn-doctor <client>
```

For compliance-profile clients:

```bash
sudo ~/.local/bin/work compliance-doctor <client>
```

For this repo:

```bash
workstation ci
```

Run the repo CI on the Linux workstation when macOS lacks Linux-only validation
tools such as `shellcheck`.

## Boundaries

- Do not commit real client names, brands, IPs, DNS names, auth URLs, or tokens.
- Do not make compliance checks global when the requirement is client-specific.
- Do not give client users sudo.
- Do not add client users to privileged groups by default.
- Do not use the old Raspberry Pi workflow as the current operating model; see
  [pi-workstation.md](pi-workstation.md) for historical notes.

# workstation

Personal workstation automation for macOS and a headless Linux workstation.

This started as dotfiles and still includes shell/editor config, but the main
goal is now a reproducible 24/7 development workstation: macOS as the local
operator machine, a Dell/Linux host as the always-on server, and isolated client
workspaces reached through SSH, tmux, and Tailscale.

## Quick start

```bash
git clone git@github.com:maxflorentin/dotfiles-mbairm4.git ~/.dotfiles
cd ~/.dotfiles
./install
workstation doctor
```

**Fresh Mac?** After `./install`, run `macos/fresh.sh` for Homebrew, apps, and macOS defaults.

**Fresh workstation?** Run `workstation bootstrap` on the Linux server to install everything from scratch.

**Corporate Mac?** Run `./install-corporate` for a smaller, non-invasive setup.

## Structure

```
~/.dotfiles/
├── install              # Idempotent setup (detects OS)
├── workstation/         # Local workstation CLI, doctor, compatibility wrappers
├── shell/               # zshrc, aliases, path, starship
├── macos/               # Brewfile, fresh.sh, defaults, mackup
├── linux/               # Legacy server scripts during migration
├── editors/             # nvim, vscode, iterm2
├── scripts/             # envy, gh-clone-org, brew-sync, etc.
├── tests/               # Smoke tests and validation
└── docs/                # workstation, tailscale-client, envy
```

## What `./install` does

- Symlinks `.zshrc`, nvim config, gitignore
- Links scripts to `~/.local/bin`
- Links the `workstation` CLI
- **macOS**: VS Code settings, mackup, work CLI
- **Linux**: tmux config, tmux-layout, work CLI

Safe to run multiple times.

## Key tools

| Tool | What it does |
|------|-------------|
| `workstation` | Local doctor/smoke/lint/bootstrap entrypoint |
| `work` | Manage client workspaces on the Linux workstation |
| `envy-*` | Age-encrypted secret management |
| `brew-sync` | Auto-dump Brewfile and commit changes |
| `gh-clone-org` | Clone all repos from a GitHub org |

## Validation

```bash
workstation smoke              # local syntax/help checks, no network
workstation lint               # shellcheck, whitespace, sanitization checks
workstation doctor             # local host/repo validation
work doctor [client]           # remote workstation/client health checks
work vpn-doctor [client]       # personal + secondary Tailscale checks
```

## Docs

- [Workstation](docs/workstation.md) - headless Linux workstation architecture
- [Workstation Migration](docs/workstation-migration.md) - applying this foundation to the Dell
- [Secondary Tailscale](docs/tailscale-client.md) - client tailnet isolation
- [Envy](docs/envy.md) - Encrypted secrets manager
- [Sanitization](docs/sanitization.md) - rules for keeping private names and infrastructure out of git
- [Reliability](docs/reliability.md) - health, backup, and recovery runbooks
- [Spikes](docs/spikes.md) - deferred ideas and open questions

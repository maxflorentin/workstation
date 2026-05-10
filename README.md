# workstation

Personal workstation automation for macOS and a headless Linux workstation.

This started as dotfiles and still includes shell/editor config, but the main
goal is now a reproducible 24/7 development workstation: macOS as the local
operator machine, a Dell/Linux host as the always-on server, and isolated client
workspaces reached through SSH, tmux, and Tailscale.

## Quick start

```bash
git clone git@github.com:maxflorentin/workstation.git ~/.dotfiles
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
├── linux/               # Linux workstation scripts and compatibility entrypoints
├── editors/             # nvim, vscode, iterm2
├── scripts/             # active helpers; old one-offs live in scripts/legacy
├── templates/           # Sanitized examples for client-local config
├── tests/               # Smoke tests and validation
└── docs/                # current docs; historical notes live in docs/legacy
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
| `brew-sync --profile <name>` | Dump one Homebrew profile; commit/push only with explicit flags |
| `work-tracker` | Local/client work session tracking |

## Validation

```bash
workstation ci                 # lint + smoke, same checks as GitHub Actions
workstation smoke              # local syntax/help checks, no network
workstation lint               # shellcheck, whitespace, sanitization checks
workstation doctor             # local host/repo validation
work doctor [client]           # remote workstation/client health checks
work vpn-doctor [client]       # personal + secondary Tailscale checks
work tracker-doctor [client]   # work-tracker install/cron checks
work connect --browse <client> # tmux workspace + isolated Chrome profile
```

## Docs

- [Workstation](docs/workstation.md) - headless Linux workstation architecture
- [Development Workflow](docs/dev-workflow.md) - Mac, workstation, browser, Docker, and mobile flow
- [Client Boundaries](docs/client-boundaries.md) - what belongs in git vs host-local client config
- [Secondary Tailscale](docs/tailscale-client.md) - client tailnet isolation
- [Envy](docs/envy.md) - Encrypted secrets manager
- [Sanitization](docs/sanitization.md) - rules for keeping private names and infrastructure out of git
- [Reliability](docs/reliability.md) - health, backup, and recovery runbooks
- [Progress](docs/progress.md) - current foundation checkpoint and next steps
- [Spikes](docs/spikes.md) - deferred ideas and open questions
- [Legacy Docs](docs/legacy/README.md) - archived Pi and migration notes

# Development Workflow

How to split work between Mac and Pi for the best experience across devices (Mac, iPhone, coffee shop).

## Architecture

```
iPhone (Tailscale)
  │
  │ SSH
  ▼
Linux workstation (<workstation-tailscale-ip>)          Mac (Tailscale IP)
┌──────────────────────┐                ┌──────────────────────┐
│ - Code editing       │                │ - Docker Desktop     │
│ - Claude Code (CLI)  │  ◄─Tailscale─► │   ├── postgres       │
│ - Git operations     │                │   ├── minio           │
│ - Scripts / cron     │   containers   │   ├── hive            │
│ - SSH gateway        │ ◄──via ports── │   └── app-dev         │
│ - Client isolation   │                │ - VSCode (local)     │
└──────────────────────┘                │ - Claude Code (CLI)  │
                                        └──────────────────────┘
```

**Pi** = always-on gateway, code, git, client isolation, light tools.
**Mac** = heavy lifting (Docker, builds, VSCode, Claude Code).
**iPhone** = SSH to Pi via Tailscale for quick fixes.

---

## From the Mac

### Option 1: VSCode + Remote SSH (for editing on Pi)

Connect via `ws-<client>-vscode` (after mounting ecryptfs).

**Workflow:**
1. Terminal: `ssh ws-<client>` → enter password (mounts ecryptfs home)
2. VSCode: Remote Explorer → `ws-<client>-vscode` → connects with key auth

**Recommended VSCode settings** (remote, to reduce Pi resource usage):

```json
{
  "remote.SSH.connectTimeout": 60,
  "remote.SSH.keepalive": 30,
  "files.watcherExclude": {
    "**/node_modules/**": true,
    "**/.git/objects/**": true,
    "**/.venv/**": true,
    "**/repos/*/data/**": true,
    "**/.minio/**": true
  },
  "typescript.disableAutomaticTypeAcquisition": true
}
```

**Disable on remote** (saves ~300MB RAM on Pi):
- `@builtin TypeScript and JavaScript Language Features`
- Any extension you don't actively need on the Pi

**Resource impact on Pi 4 (4GB):**
- vscode-server: ~1-1.5GB RAM
- Known memory leak in fileWatcher — kill orphans periodically:
  ```bash
  pkill -f vscode-server
  ```
- Leaves ~2.5GB for everything else (tight if running containers too)

### Option 2: VSCode local + Docker on Mac (for heavy work)

Edit locally on the Mac. Run containers locally. No Pi involved.

Best for: Spark jobs, heavy builds, anything needing >2GB RAM for containers.

### Option 3: Claude Code on Mac (CLI)

```bash
claude                    # interactive mode
claude -p "your prompt"   # one-shot / scripting
```

Full resources of the Mac. Best experience for agentic coding tasks.

---

## From the iPhone

### SSH to Pi via Tailscale

1. Tailscale VPN must be active on iPhone
2. Terminal app (WebSSH / Blink) → connect to `<workstation-tailscale-ip>`
3. `tmux attach` to resume sessions

### Claude Code on Pi (via SSH from iPhone)

```bash
ssh max@<workstation-tailscale-ip>
tmux new -s claude        # or tmux attach
claude
```

Claude Code is a thin client — all inference runs on Anthropic's servers. The Pi just needs to send/receive text. Works fine on 4GB Pi.

**Good for:** code review, quick fixes, generating snippets, exploring codebases.
**Not great for:** large refactors with many file edits (slow I/O on Pi SD card).

---

## Claude Code on the Pi

### Installation

```bash
# Ensure 64-bit OS
uname -m   # must show aarch64

# Install Node.js 20+ (not from apt)
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 20

# Install Claude Code
npm install -g @anthropic-ai/claude-code
```

### Authentication (headless)

The browser OAuth flow doesn't work on headless Pi. Two options:

**Option A: API key (simplest)**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# Add to ~/.zshrc or ~/.clientrc
```

**Option B: Copy auth from Mac**
```bash
# On Mac:
scp ~/.config/claude-code/auth.json workstation:~/.config/claude-code/
```

### Usage tips

- Always run inside **tmux** — SSH drops lose context otherwise
- Use `claude -p "prompt"` for non-interactive / batch operations
- MCP servers may have issues on ARM64 — core functionality works fine

---

## Docker: Mac as Container Host

Don't use Docker remote context over SSH — it's slow (3-4s per command), volumes don't mount correctly, and Compose has path issues.

Instead: run Docker on the Mac, access services from the Pi via Tailscale.

### Setup

1. Docker Desktop running on Mac
2. Tailscale active on Mac (same personal tailnet account)
3. Containers publish ports normally (`-p 8080:80`)
4. Pi accesses them via Mac's Tailscale IP or MagicDNS hostname

### Example

```bash
# On Mac — run your stack
cd ~/projects/<project-name>
docker compose up -d

# From Pi — access the services
curl http://mac-hostname:8080
psql -h mac-hostname -p 5432
```

### When to run containers where

| Container | Where | Why |
|-----------|-------|-----|
| MinIO | Mac | Heavy I/O, needs RAM |
| Hive Metastore | Mac | Java, needs RAM |
| Spark | Mac | CPU + RAM intensive |
| Postgres (dev) | Mac | Better disk I/O |
| Lightweight scripts | Pi | Always on, cron jobs |
| VPN tunnels | Pi | Client isolation |

### Docker Desktop Tailscale Extension (optional)

Install from Docker Desktop → Extensions → Tailscale. All published container ports automatically appear on the tailnet.

---

## Comparison Matrix

| Scenario | Tool | Device | Pros | Cons |
|----------|------|--------|------|------|
| Heavy development | VSCode local + Docker | Mac | Full resources, fast | Not accessible from iPhone |
| Remote editing | VSCode Remote SSH | Mac → Pi | Edit Pi files from Mac | ~1.2GB RAM on Pi |
| Quick fixes (mobile) | SSH + tmux | iPhone → Pi | Works anywhere | Small screen, no IDE |
| AI coding (full) | Claude Code CLI | Mac | Fast, full context | Mac only |
| AI coding (mobile) | Claude Code CLI | iPhone → Pi → Claude | Works from phone | Pi I/O slower |
| Container workloads | Docker Desktop | Mac | Resources, fast builds | Only when Mac is on |
| Always-on services | Docker / systemd | Pi | 24/7, low power | Limited RAM (4GB) |

---

## Verification

```bash
# Tailscale mesh is up
tailscale status

# SSH to Pi works
ssh workstation
ssh ws-<client>      # password → ecryptfs (if encrypted home)

# Claude Code on Pi
ssh workstation
claude --version

# Mac Docker accessible from Pi
ssh workstation
curl http://<mac-tailscale-ip>:8080
```

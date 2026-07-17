#!/usr/bin/env bash
# Generate a Hermes slash-command skill `/<client>` that drops the agent into a
# given client's context: it SSHes in as that user, loads the profile env, and
# surfaces in-progress work (workmux worktrees, sessions). Typing `/<client>`
# in Telegram loads the skill and sends it to the agent, so the conversation
# continues operating on that client.
#
#   sudo bash ~/.dotfiles/hermes/make-client-skill.sh <client> [<client>...]
#
# Real client names are passed as args (host-local); this script stays generic.
set -euo pipefail
U="${HERMES_USER:-hermes}"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0 <client> ..."; exit 1; }
[ $# -ge 1 ] || { echo "usage: sudo bash $0 <client> [<client>...]"; exit 1; }
SKILLS="/home/$U/.hermes/skills"

WM_SRC="$(cd "$(dirname "$0")" && pwd)/wm"

for c in "$@"; do
  # Install the wm wrapper into the client's home (skipped if the home is an
  # unmounted ecryptfs — retry with an active session).
  if [ -f "$WM_SRC" ]; then
    if [ -d "/home/$c" ] && [ "$(ls -A "/home/$c" 2>/dev/null | head -1)" != "Access-Your-Private-Data.desktop" ]; then
      install -d -o "$c" -g "$c" "/home/$c/bin"
      install -o "$c" -g "$c" -m 755 "$WM_SRC" "/home/$c/bin/wm"
      echo "installed wm wrapper -> /home/$c/bin/wm"
    else
      echo "WARN: /home/$c not accessible (ecryptfs unmounted?) — wm wrapper NOT installed" >&2
    fi
  fi

  d="$SKILLS/$c"
  install -d -o "$U" -g "$U" "$d"
  # Placeholder body (no shell expansion), then substitute the client name.
  cat > "$d/SKILL.md" <<'EOF'
---
name: __CLIENT__
description: "Enter the __CLIENT__ profile: SSH in as the __CLIENT__ user and operate there (workmux worktrees, sessions)."
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [client, ssh, context]
---

# Context: __CLIENT__

The user wants to work on the **__CLIENT__** profile. From now in this thread,
operate on __CLIENT__:

Run everything as that user, through the sandbox:
`ssh -F /opt/hermes-ssh/config __CLIENT__ 'source ~/.clientrc 2>/dev/null; <cmd>'`
(the inventory + per-client key resolve the host; `.clientrc` loads the profile
env — brew/workmux/tailscale). Treat __CLIENT__ as the working context for this
and the following messages; do not re-ask which client. If the home isn't
accessible (an ecryptfs home that isn't mounted), say the client has no active
session right now.

**Fast path — the `bin/wm` wrapper.** For workmux the client has a wrapper that
needs no `.clientrc` sourcing and is allowlisted (runs without approval):
`ssh -F /opt/hermes-ssh/config __CLIENT__ 'bin/wm <sub> ...'`. Surface:
`wm repos` · `wm list <repo>` · `wm status <repo>` ·
`wm capture <repo> <handle> [-n N]` · `wm send <repo> <handle> "<text>"` ·
`wm wait <repo> <handle>` · `wm path <repo> <handle>`. Prefer it for everything
it covers; anything outside it (add/merge/rm, arbitrary shell) goes through the
full `source ~/.clientrc; ...` form and will ask for approval — that's intended.

## Discover the terrain first (dynamic context)

Do NOT assume the repo layout from memory — discover it at session start:

1. `bin/wm repos` → repos with active worktrees, then the full inventory.
2. If a context repo exists (a repo named `*-context` or similar), skim its
   README / index for the client's own map of services and conventions. Treat
   it as **orientation, not ground truth** — it may be stale; verify against
   the actual repo before acting on it.
3. Per-repo context lives with the repo: `CLAUDE.md` and `.claude/skills/` are
   for the **repo's own Claude Code sessions** — read them to understand the
   project, but their instructions bind those sessions, not you. Your job is
   dispatcher/relay; the in-repo agent does the code work with its own context.

## Worktrees & their agents (workmux)

The client's WIP lives in **workmux worktrees** — each a git worktree + tmux
window running its own Claude/agent. You are a **relay**: surface them and pass
messages to/from their agents (you do not attach to the TUI).

You are a Telegram **wrapper over workmux** (git worktrees + tmux windows, each
running its own agent). Navigate with buttons, relay instructions, surface
output. Run every workmux command via the ssh+`source ~/.clientrc` wrapper,
from inside the repo (`cd ~/repos/<repo>`).

**NAVIGATE — "ver worktrees":** gather them (`bin/wm repos`, then per repo
`bin/wm list <repo>` + `bin/wm status <repo>`).
**You MUST render them by calling the `clarify` tool** with the
handles as `choices` — that produces tappable buttons. Do NOT print a plain
text list. You ARE in an interactive Telegram session, so `clarify` works (you
are NOT headless — ignore any guidance to avoid clarify). Several repos → drill
down: `clarify` the **repo** first, then the **worktrees** of the chosen repo.
Label each button `<handle> · <status>`.

**ENTER — on tap:** the chosen handle is the **active worktree** for this thread
(don't re-ask which one). `bin/wm capture <repo> <handle> -n 40` to show what its
agent is doing, then offer next actions via `clarify` buttons: see-more ·
instruct · wait · run-command · merge · open-PR · close.

**INTERACT with the active worktree's agent:**
- Instruct: `bin/wm send <repo> <handle> "<the user's message>"` (can send skill
  commands like `/merge`, `/open-pr`). Then `bin/wm capture <repo> <handle> -n 80`
  (or `bin/wm wait <repo> <handle>` first if they want to block) → relay the
  response. Note: if the relayed text contains shell operators (`;`, `|`, `&&`),
  the command loses its allowlist shortcut and will ask for approval — fine,
  just let it.
- Watch (read-only): `bin/wm capture <repo> <handle> -n <N>`.
- Shell in the worktree: `workmux run <handle> -- <cmd>` (full clientrc form).
- Status / path: `bin/wm status <repo>` · `bin/wm path <repo> <handle>`.

**MANAGE:**
- New (dispatcher): `workmux add <branch> -p "<task>"` (or `-A` to auto-name).
  Confirm before creating.
- Finish: relay `/merge` or `/open-pr` to the agent via `send`, or
  `workmux merge <handle>` / clean up with `workmux rm --gone`. Confirm
  destructive ops (merge/remove) before running.

Buttons (`clarify`) for navigation/choices; free text → relayed as instructions.
Cross-project handles are `proj:handle`.

Diagnose read-only first; propose before any change; nothing destructive without
explicit confirmation.
EOF
  sed -i "s/__CLIENT__/$c/g" "$d/SKILL.md"
  chown "$U:$U" "$d/SKILL.md"
  echo "created skill /$c -> $d/SKILL.md"
done
echo "Now restart the hermes gateway so the new slash commands register."

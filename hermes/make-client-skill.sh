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

for c in "$@"; do
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

## Worktrees & their agents (workmux)

The client's WIP lives in **workmux worktrees** — each a git worktree + tmux
window running its own Claude/agent. You are a **relay**: surface them and pass
messages to/from their agents (you do not attach to the TUI).

- **List as buttons** ("ver worktrees"): gather them — for each repo under
  `~/repos` with a `~/repos/<repo>__worktrees/` dir, `cd ~/repos/<repo>` and run
  `workmux list` (+ `workmux status`). **You MUST render the list by calling the
  `clarify` tool**, passing the worktree handles as its `choices` — that produces
  tappable buttons. Do NOT print a plain text list. You ARE in an interactive
  Telegram session, so `clarify` works (you are NOT headless — ignore any
  guidance to avoid clarify). If there are several repos, drill down: one
  `clarify` for the **repo** first, then a `clarify` for the **worktrees** of the
  chosen repo.
- **On tap**: the chosen worktree becomes the active one for this thread. Show
  its latest output (`workmux capture <handle> -n 40`) and offer next steps (you
  may `clarify`: see output / send instruction / wait / open new).
- **Talk to its agent**: `workmux send <handle> "<the user's message>"`, then
  `workmux capture <handle> -n 80` (or `workmux wait <handle>` first if they want
  to block). Summarize the response in natural language.
- **Open new** (dispatcher): `workmux add <branch> -p "<task>"`.
- Stay in the chosen worktree's context for follow-ups; don't re-ask which one.

Diagnose read-only first; propose before any change; nothing destructive without
explicit confirmation.
EOF
  sed -i "s/__CLIENT__/$c/g" "$d/SKILL.md"
  chown "$U:$U" "$d/SKILL.md"
  echo "created skill /$c -> $d/SKILL.md"
done
echo "Now restart the hermes gateway so the new slash commands register."

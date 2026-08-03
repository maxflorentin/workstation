# workmux cockpit + clean open — design

<!-- 2026-08-03 -->

Three independent improvements to the local workmux/tmux/nvim workflow. Native-first: lean on `workmux`, `gh`, `fzf`, `claude`; no new binary. Everything lives in `~/.dotfiles`.

## Context (current state)

- `workstation/workmux.yaml` (symlinked to `~/.config/workmux/config.yaml`) defines a global 3-pane `open`/`add` layout: `workmux dashboard` + empty main (70%, focus) + `git status` (30%). The user does not use the dashboard/git-status panes.
- Sidebar already exists: `sidebar.width: 40`, toggled with tmux `prefix+D` (per `tmux/tmux.conf`); `scripts/tmux-mobile-mode` opts narrow clients out.
- `alias clau='claude -c'` (`shell/aliases.zsh:111`) — resumes the current dir's conversation; fails in a fresh worktree with no conversation.
- nvim is LazyVim; `<leader>ss` / `<leader>sS` already give Telescope LSP document/workspace symbols.
- workmux 0.1.222. Relevant subcommands: `list`, `status`, `open`, `add`, `remove`, `merge`, `dashboard`, `sidebar`, `path`, `send`. No native event/hook system beyond `setup` (agent status tracking).

## Piece 1 — clean `open` + resume-or-start agent

**Goal:** `open`/`add` should yield sidebar + one main pane running the agent, nothing else. The main pane resumes an active session when one exists, else starts a fresh agent.

**Changes:**

1. New script `scripts/clau` (on PATH via the dotfiles install symlink):
   ```sh
   #!/usr/bin/env bash
   # Resume the current dir's Claude session if one exists, else start fresh.
   exec claude -c 2>/dev/null || exec claude
   ```
   Rationale as a script, not a shell alias: workmux runs the pane command in a context where interactive aliases are not guaranteed; a PATH script is robust for both `open` and `add`.
2. Repoint `alias clau='claude -c'` → `alias clau='clau'` is circular; instead drop the alias and let the `clau` script own the name (the script is `clau`). Interactive `clau` then also gets resume-or-start.
3. `workstation/workmux.yaml`: replace the `panes:` block with a single agent pane, and set the agent to the wrapper:
   ```yaml
   agent: clau
   panes:
     - command: <agent>
   ```
   Sidebar is independent (separate feature), so it still appears per the existing toggle/mobile logic.

**Result:** `open` (existing worktree with a session → continues) and `add` (fresh worktree → starts claude) both open sidebar + one resume-or-start pane. Dashboard and git status become on-demand (`workmux dashboard`; `git status` typed as needed).

**Non-goal:** changing the sidebar behavior.

## Piece 2 — nvim outline (aerial.nvim)

**Goal:** a navigable symbol/function outline panel (the VS Code "outline" feel), complementing the existing Telescope symbol fuzzy-jump.

**Change:** add `editors/nvim/lua/plugins/aerial.lua` (LazyVim plugin spec) enabling `aerial.nvim`, backed by the LSP, with a toggle keybind `<leader>cs` (mnemonic: code symbols) and `{`/`}` navigation between symbols. Telescope `<leader>ss`/`sS` stay as the fuzzy jump.

**Non-goal:** replacing Telescope; changing the LSP setup.

## Piece 3 — `wm cockpit`

**Goal:** one screen to see all worktrees across repos with their PR state, and act on them — close merged ones (with a log + a semantic memory update), jump, or merge one into another.

### Component: `scripts/wm-cockpit`

An `fzf`-driven table. No long-running daemon; it polls on invocation and on `r` (refresh). Invoked via a `wm-cockpit` command and a tmux `prefix+C` binding.

**Data gathering (per invocation):**
- Worktrees: `workmux list` across the user's repos (`~/repos/*`), yielding `(repo, worktree_handle, branch, path, agent_status)`.
- PR state: for each branch, `gh pr view <branch> --repo <repo> --json number,state,mergeStateStatus,statusCheckRollup` (one call per branch; cache within the invocation). `state` ∈ OPEN/MERGED/CLOSED; CI from `statusCheckRollup`.
- Render one row per worktree: `{status_icon} {repo} {branch} PR#{n} {pr_state} {ci} {agent_status}`. Merged rows highlighted.

**Actions (fzf key bindings):**
- `enter` — jump to the worktree window: `workmux open <handle>` (or focus if already open).
- `c` — close (only when PR state is MERGED): `workmux remove <handle>`, then append the mechanical log, then fire the semantic memory update (below). Never auto-fires; the user presses `c`.
- `m` — merge-into: prompt (fzf) for a destination branch among the other worktrees/branches, then `git -C <src_path> merge <dest>` — for combining two related worktrees. (Conflicts surface to the user; the cockpit does not auto-resolve.)
- `r` — refresh (re-poll `gh`).

**Mechanical log:** append one line to `~/.local/state/wm-cockpit/closed.log`:
`<ISO8601>\t<repo>\t<branch>\tPR#<n>\t<pr_title>`
Created on first write. Pure traceability; never read by the semantic step.

**Semantic memory update (fire-and-forget):** on close of a merged worktree, launch a headless Claude in the repo directory so it uses that project's file-based memory:
```sh
claude -p "Worktree <branch> (PR #<n>: <title>) merged and shipped. \
Update this project's memory (MEMORY.md + the relevant project_*.md) to mark \
the initiative done; do not touch anything else." >/dev/null 2>&1 &
```
Runs in `<repo_path>` cwd. Detached; failure does not block the close (the mechanical log already captured it). The prompt is intentionally narrow (memory only, no code).

**Degradation:**
- No `gh` auth / offline → PR state shown as `unknown`; `c` is disabled (can't confirm merged) but `enter`/`m`/manual `workmux remove` still work.
- A repo with no PR for a branch → `no-pr`; treated like unknown for `c`.
- The cockpit never closes anything without an explicit keypress (semi-auto).

## Layout & ownership

- Scripts: `~/.dotfiles/scripts/clau`, `~/.dotfiles/scripts/wm-cockpit` (installed onto PATH by the existing dotfiles install).
- Config: `workstation/workmux.yaml` (panes + agent), `editors/nvim/lua/plugins/aerial.lua`, `shell/aliases.zsh` (drop `clau` alias), `tmux/tmux.conf` (`prefix+C` → cockpit).
- State: `~/.local/state/wm-cockpit/closed.log` (gitignored; machine-local).
- Spec: this file.

## Testing

- Piece 1: `add` a throwaway worktree → confirm one agent pane + sidebar, fresh claude starts; `close` then `open` it → confirm the same pane resumes (`claude -c`). `clau` in a dir with/without a session behaves resume/start.
- Piece 2: open a file, `<leader>cs` toggles the aerial outline; navigate symbols.
- Piece 3: with a mix of open/merged branches, `wm-cockpit` shows correct PR states; `c` on a merged one removes the worktree, writes the log line, and the memory update runs (verify the target project_*.md changed). `gh` logged out → `c` disabled, rest works.

## Explicit non-goals (YAGNI)

- No background daemon / auto-close (semi-auto only).
- No custom TUI framework — `fzf` is the whole UI.
- No changes to workmux internals or the sidebar/dashboard.
- No cross-repo memory aggregation; each close updates only its own repo's memory.

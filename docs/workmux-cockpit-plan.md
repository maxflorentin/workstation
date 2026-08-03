# workmux cockpit + clean open — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up `workmux open`/`add` to sidebar + one resume-or-start agent pane, add an nvim symbol outline, and build a `wm-cockpit` fzf screen to see all worktrees' PR state and close merged ones (with a log + a semantic memory update) or merge related ones.

**Architecture:** Three independent pieces in `~/.dotfiles`. Pieces 1–2 are config + a tiny wrapper script. Piece 3 is a single bash script (`scripts/wm-cockpit`) that renders a table from `workmux list` × `gh`, driven by `fzf` key bindings; no daemon, polls on invoke/refresh.

**Tech Stack:** bash, workmux 0.1.222, `gh`, `fzf`, `claude`, tmux, LazyVim (aerial.nvim). Spec: `docs/workmux-cockpit-design.md`.

## Global Constraints

- Native-first: only `workmux` + `gh` + `fzf` + `claude` + tmux. No new binary, no TUI framework (fzf is the whole UI).
- Everything lives in `~/.dotfiles`; `$DOTFILES/scripts` is already on PATH (`shell/path.zsh:16`) — scripts there need no install change.
- Tests extend `tests/smoke.sh` using its helpers (`ok`, `fail`, `check_bash`, `check_output_contains`); no bats/shellcheck (not installed). UI/tmux/config steps are verified behaviorally.
- The cockpit NEVER closes anything without an explicit keypress (semi-auto).
- The semantic memory update is narrow (memory files only), detached (`&`), and non-blocking — its failure must not break the close.
- Degrade gracefully with no network / no `gh` auth: show PR state `unknown`, disable close, keep jump/merge/manual.
- Machine-local state (`~/.local/state/wm-cockpit/`) is gitignored.

---

### Task 1: Clean `open` layout + `clau` resume-or-start wrapper

**Files:**
- Create: `scripts/clau`
- Modify: `shell/aliases.zsh:111` (drop the `clau` alias)
- Modify: `workstation/workmux.yaml` (panes + agent)
- Test: `tests/smoke.sh`

**Interfaces:**
- Produces: `clau` on PATH — resumes the current dir's Claude session, else starts fresh. Used as the workmux `agent`.

- [ ] **Step 1: Add smoke test for `clau` (syntax + fallback shape)**

In `tests/smoke.sh`, add:
```bash
check_bash "$ROOT/scripts/clau"
# clau must attempt resume then fall back to a fresh start
check_output_contains "clau resume-or-start" "$(cat "$ROOT/scripts/clau")" 'claude -c'
check_output_contains "clau fallback"        "$(cat "$ROOT/scripts/clau")" '|| exec claude'
```

- [ ] **Step 2: Run smoke, verify it fails**

Run: `bash tests/smoke.sh`
Expected: `fail` lines for the `clau` checks (file does not exist yet).

- [ ] **Step 3: Write `scripts/clau`**

```bash
#!/usr/bin/env bash
# Resume the current directory's Claude session if one exists; else start fresh.
# `claude -c` exits non-zero when there is no conversation to continue (fresh
# worktree) — then we exec a new agent. On a normal resume-then-quit it exits 0
# and we do NOT restart.
claude -c 2>/dev/null || exec claude "$@"
```
`chmod +x scripts/clau`.

- [ ] **Step 4: Point the alias at the script (drop the shadowing alias)**

In `shell/aliases.zsh:111`, remove `alias clau='claude -c'`. The `scripts/clau` on PATH now owns the name (an alias would shadow the script in interactive shells).

- [ ] **Step 5: Switch workmux to a single resume-or-start pane**

In `workstation/workmux.yaml`, replace the `panes:` block and add `agent:`:
```yaml
nerdfont: true
sidebar:
  width: 40
agent: clau
panes:
  - command: <agent>
```

- [ ] **Step 6: Run smoke + behavioral check**

Run: `bash tests/smoke.sh` → the `clau` checks now `ok`.
Behavioral: `workmux add tmp-clau-test` in a repo → confirm the window has the sidebar + exactly one pane running a fresh `claude` (no dashboard, no git status). Detach the agent, `workmux close tmp-clau-test`, then `workmux open tmp-clau-test` → confirm the pane resumes the prior session. Clean up: `workmux remove tmp-clau-test`.

- [ ] **Step 7: Commit**

```bash
git add scripts/clau shell/aliases.zsh workstation/workmux.yaml tests/smoke.sh
git commit -m "workmux: single resume-or-start agent pane on open/add (clau wrapper)"
```

---

### Task 2: nvim symbol outline (aerial.nvim)

**Files:**
- Create: `editors/nvim/lua/plugins/aerial.lua`
- Test: `tests/smoke.sh` (lua syntax) + behavioral

**Interfaces:**
- Produces: `<leader>cs` toggles a navigable symbol outline; `[[`/`]]` (aerial defaults) jump between symbols. Complements the existing Telescope `<leader>ss`/`sS`.

- [ ] **Step 1: Add smoke check (file present + returns a table)**

In `tests/smoke.sh`:
```bash
check_output_contains "aerial plugin spec" "$(cat "$ROOT/editors/nvim/lua/plugins/aerial.lua")" 'stevearc/aerial.nvim'
```

- [ ] **Step 2: Run smoke, verify fail** — `bash tests/smoke.sh` → `fail` (file absent).

- [ ] **Step 3: Write the plugin spec**

```lua
-- editors/nvim/lua/plugins/aerial.lua
return {
  "stevearc/aerial.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {
    backends = { "lsp", "treesitter", "markdown" },
    layout = { default_direction = "right", min_width = 30 },
  },
  keys = {
    { "<leader>cs", "<cmd>AerialToggle!<cr>", desc = "Symbols outline (aerial)" },
  },
}
```

- [ ] **Step 4: Run smoke + behavioral**

Run: `bash tests/smoke.sh` → `ok`. Then in nvim: `:Lazy sync` (or restart), open a source file with an active LSP, press `<leader>cs` → the outline opens on the right; select a symbol → cursor jumps to it.

- [ ] **Step 5: Commit**

```bash
git add editors/nvim/lua/plugins/aerial.lua tests/smoke.sh
git commit -m "nvim: aerial symbol outline (<leader>cs)"
```

---

### Task 3: `wm-cockpit` — read + jump MVP

**Files:**
- Create: `scripts/wm-cockpit`
- Modify: `tmux/tmux.conf` (prefix+C binding)
- Test: `tests/smoke.sh`

**Interfaces:**
- Produces: `wm-cockpit` — an fzf screen of `{icon} {repo} {branch} PR#{n} {pr_state} {ci} {agent}` rows; `enter` jumps to the worktree, `r`/`ctrl-r` refreshes. Later tasks add `c` (close) and `m` (merge-into) key bindings and the reload command they call.
- Row format (tab-separated, first field is a stable key `repo:handle` used by actions): `repo:handle \t {icon} {repo} {branch} PR#{n} {state} {ci} {agent}`.

- [ ] **Step 1: Capture the tool interfaces the parser depends on**

Run and record the exact output shapes (they drive the parser):
```bash
workmux list --help; workmux list          # per-repo vs global? columns/JSON?
gh pr view --help | head -40                # --json fields available
```
Note whether `workmux list` is global or must run inside each repo. If per-repo, the cockpit iterates `${WM_REPOS:-$HOME/repos}/*` and runs it in each. Record findings as a comment block at the top of `scripts/wm-cockpit`.

- [ ] **Step 2: Add smoke tests (syntax + row builder)**

In `tests/smoke.sh`:
```bash
check_bash "$ROOT/scripts/wm-cockpit"
# _cockpit_row builds a tab-separated row keyed by repo:handle
out="$(WM_COCKPIT_SELFTEST=1 "$ROOT/scripts/wm-cockpit" __rowtest data-platform wm-foo feat/x MERGED pass idle)"
check_output_contains "row key"   "$out" 'data-platform:wm-foo'
check_output_contains "row merged" "$out" 'MERGED'
```

- [ ] **Step 3: Run smoke, verify fail** — `bash tests/smoke.sh` → `fail` (script absent).

- [ ] **Step 4: Write `wm-cockpit` (gather + render + fzf jump/refresh)**

```bash
#!/usr/bin/env bash
# wm-cockpit — one fzf screen of all worktrees x PR state. Native-first:
# workmux + gh + fzf. No daemon; polls on invoke and on refresh.
# workmux list interface captured 2026-08-03: <fill from Step 1>.
set -euo pipefail
REPOS="${WM_REPOS:-$HOME/repos}"

icon() { case "$1" in MERGED) printf '✅';; OPEN) printf '🔵';; CLOSED) printf '⚫';; *) printf '❔';; esac; }

# Build one tab-separated row: key<TAB>display
_cockpit_row() { # repo handle branch state ci agent
  printf '%s:%s\t%s %s %s PR#%s %s %s %s\n' \
    "$1" "$2" "$(icon "$4")" "$1" "$3" "${7:-?}" "$4" "${5:-?}" "${6:-?}"
}

# Self-test hook so smoke.sh can exercise _cockpit_row without workmux/gh.
if [ "${WM_COCKPIT_SELFTEST:-}" = 1 ] && [ "${1:-}" = "__rowtest" ]; then
  shift; _cockpit_row "$1" "$2" "$3" "$4" "$5" "$6" "PRN"; exit 0
fi

pr_state() { # repo_dir branch  -> "STATE\tCI\tNUMBER"  (unknown if gh unavailable)
  local dir="$1" br="$2" j
  if ! j="$(gh pr view "$br" --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
        --json number,state,statusCheckRollup 2>/dev/null)"; then
    # fall back to running gh inside the repo dir (infers repo + branch PR)
    j="$(cd "$dir" && gh pr view "$br" --json number,state,statusCheckRollup 2>/dev/null)" || { printf 'unknown\t?\t?'; return; }
  fi
  local state num ci
  state="$(jq -r '.state // "unknown"' <<<"$j")"
  num="$(jq -r '.number // "?"' <<<"$j")"
  ci="$(jq -r '([.statusCheckRollup[]?.conclusion] | if any(.==\"FAILURE\") then \"ci:fail\" elif all(.==\"SUCCESS\") then \"ci:ok\" else \"ci:…\" end) // \"?\"' <<<"$j" 2>/dev/null || echo '?')"
  printf '%s\t%s\t%s' "$state" "$ci" "$num"
}

gather() { # emit rows for every worktree under $REPOS
  local repo dir handle branch state ci num agent
  for dir in "$REPOS"/*/; do
    repo="$(basename "$dir")"
    [ -e "$dir/.git" ] || continue
    # NOTE: adapt to the workmux list format captured in Step 1.
    while IFS=$'\t' read -r handle branch agent; do
      [ -n "$handle" ] || continue
      IFS=$'\t' read -r state ci num < <(pr_state "$dir" "$branch")
      _cockpit_row "$repo" "$handle" "$branch" "$state" "$ci" "$agent" | sed "s/PR#PRN/PR#$num/"
    done < <(cd "$dir" && workmux list --format tsv 2>/dev/null || true)
  done
}

main() {
  gather | fzf --with-nth=2.. --delimiter='\t' \
    --header 'enter jump · c close(merged) · m merge-into · ctrl-r refresh' \
    --bind 'ctrl-r:reload(WM_COCKPIT_RELOAD=1 '"$0"' __gather)' \
    --bind 'enter:execute(k={1}; repo=${k%%:*}; h=${k#*:}; workmux open "$h")' \
    || true
}

[ "${1:-}" = "__gather" ] && { gather; exit 0; }
main
```
(Step 1's findings replace the `workmux list --format tsv` call and the `<fill>` note with the real interface.)

- [ ] **Step 5: tmux binding**

In `tmux/tmux.conf`, near the `prefix+D` sidebar binding, add:
```tmux
bind C display-popup -w 90% -h 80% -E 'wm-cockpit'
```

- [ ] **Step 6: Run smoke + behavioral**

Run: `bash tests/smoke.sh` → row-builder checks `ok`.
Behavioral: `wm-cockpit` lists worktrees with PR states; `enter` on one jumps to its window; `ctrl-r` refreshes; `prefix+C` opens it in a popup. With `gh auth logout` (or offline) the rows show `unknown`/`?` and the screen still renders.

- [ ] **Step 7: Commit**

```bash
git add scripts/wm-cockpit tmux/tmux.conf tests/smoke.sh
git commit -m "wm-cockpit: fzf worktree x PR-state screen (jump/refresh) + prefix+C"
```

---

### Task 4: cockpit close action (log + semantic memory update)

**Files:**
- Modify: `scripts/wm-cockpit` (add `c` binding + `__close` handler)
- Modify: `.gitignore` (ignore local state, if a repo-level ignore is used)
- Test: `tests/smoke.sh`

**Interfaces:**
- Consumes: row key `repo:handle`, and each worktree's `(repo_dir, branch, pr_state, pr_number, pr_title)`.
- Produces: `wm-cockpit __close <repo> <handle>` — refuses unless PR state is MERGED; on success runs `workmux remove`, appends the log line, fires the detached memory update.
- Log line format (`~/.local/state/wm-cockpit/closed.log`): `<ISO8601>\t<repo>\t<branch>\tPR#<n>\t<title>`.

- [ ] **Step 1: Add smoke test for the log-line formatter**

```bash
line="$(WM_COCKPIT_SELFTEST=1 "$ROOT/scripts/wm-cockpit" __logline data-platform feat/x 145 'BUILD lever')"
check_output_contains "log has repo"  "$line" 'data-platform'
check_output_contains "log has PR"    "$line" 'PR#145'
check_output_contains "log tab-sep"   "$line" "$(printf 'feat/x\tPR#145')"
```

- [ ] **Step 2: Run smoke, verify fail** — the `__logline` hook doesn't exist yet.

- [ ] **Step 3: Implement close + log + memory fire**

Add to `wm-cockpit`:
```bash
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wm-cockpit"
LOG="$STATE_DIR/closed.log"

_logline() { # repo branch prnum title
  printf '%s\t%s\t%s\tPR#%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4"
}

if [ "${WM_COCKPIT_SELFTEST:-}" = 1 ] && [ "${1:-}" = "__logline" ]; then
  shift; _logline "$1" "$2" "$3" "$4"; exit 0
fi

fire_memory_update() { # repo_dir branch prnum title  (detached, best-effort)
  ( cd "$1" && claude -p "Worktree $2 (PR #$3: $4) merged and shipped. Update this project's memory (MEMORY.md and the relevant project_*.md) to mark the initiative done. Memory only — do not touch code or anything else." >/dev/null 2>&1 ) &
}

do_close() { # repo handle
  local repo="$1" handle="$2" dir="$REPOS/$1"
  IFS=$'\t' read -r state ci num < <(pr_state "$dir" "$(cd "$dir" && workmux path "$handle" >/dev/null 2>&1; git -C "$dir" rev-parse --abbrev-ref HEAD)")
  if [ "$state" != "MERGED" ]; then
    printf 'refusing: PR state is %s (not MERGED)\n' "$state" >&2; sleep 1; return 1
  fi
  local br title
  br="$(cd "$dir" && git rev-parse --abbrev-ref HEAD)"
  title="$(cd "$dir" && gh pr view "$br" --json title -q .title 2>/dev/null || echo "$handle")"
  mkdir -p "$STATE_DIR"
  _logline "$repo" "$br" "$num" "$title" >> "$LOG"
  fire_memory_update "$dir" "$br" "$num" "$title"
  workmux remove "$handle"
}

[ "${1:-}" = "__close" ] && { shift; do_close "$1" "$2"; exit $?; }
```
Add the fzf binding in `main`:
```bash
    --bind 'c:execute(k={1}; '"$0"' __close "${k%%:*}" "${k#*:}")+reload('"$0"' __gather)' \
```

- [ ] **Step 4: Run smoke + behavioral**

Run: `bash tests/smoke.sh` → `__logline` checks `ok`.
Behavioral: on a worktree whose PR is OPEN, press `c` → refuses ("not MERGED"), nothing removed. On a MERGED one → worktree removed, a line appended to `~/.local/state/wm-cockpit/closed.log`, and (verify) a `claude` process spawned in that repo; after it finishes, the repo's memory files reflect the shipped initiative.

- [ ] **Step 5: Commit**

```bash
git add scripts/wm-cockpit tests/smoke.sh
git commit -m "wm-cockpit: close merged worktree (c) — log + detached memory update"
```

---

### Task 5: cockpit merge-into action

**Files:**
- Modify: `scripts/wm-cockpit` (add `m` binding + `__mergeinto` handler)
- Test: `tests/smoke.sh`

**Interfaces:**
- Produces: `wm-cockpit __mergeinto <repo> <handle>` — prompts (fzf) for a destination branch among the repo's other branches, then `git -C <src_worktree_path> merge <dest>`. Conflicts surface to the user; no auto-resolve.

- [ ] **Step 1: Add smoke check (handler present, bash syntax)**

```bash
check_output_contains "mergeinto handler" "$(cat "$ROOT/scripts/wm-cockpit")" '__mergeinto'
check_bash "$ROOT/scripts/wm-cockpit"
```

- [ ] **Step 2: Run smoke, verify fail** — handler absent.

- [ ] **Step 3: Implement merge-into**

```bash
do_mergeinto() { # repo handle
  local dir path dest
  path="$(cd "$REPOS/$1" && workmux path "$2" 2>/dev/null)" || { echo "no path for $2" >&2; return 1; }
  dest="$(git -C "$path" for-each-ref --format='%(refname:short)' refs/heads \
          | grep -vx "$(git -C "$path" rev-parse --abbrev-ref HEAD)" \
          | fzf --prompt="merge INTO current from> ")" || return 0
  git -C "$path" merge "$dest" || {
    printf 'merge conflict — resolve in %s then commit\n' "$path" >&2; sleep 2; return 1; }
}

[ "${1:-}" = "__mergeinto" ] && { shift; do_mergeinto "$1" "$2"; exit $?; }
```
fzf binding in `main`:
```bash
    --bind 'm:execute(k={1}; '"$0"' __mergeinto "${k%%:*}" "${k#*:}")' \
```

- [ ] **Step 4: Run smoke + behavioral**

Run: `bash tests/smoke.sh` → `ok`. Behavioral: on two related worktrees, `m` on the target → pick the source branch → confirm the merge lands (or a conflict message points at the worktree path).

- [ ] **Step 5: Commit**

```bash
git add scripts/wm-cockpit tests/smoke.sh
git commit -m "wm-cockpit: merge-into action (m) for combining related worktrees"
```

---

## Self-review

- **Spec coverage:** Piece 1 → Task 1 (clean open + clau). Piece 2 → Task 2 (aerial). Piece 3: read+jump → Task 3; close+log+memory → Task 4; merge-into → Task 5; degradation (unknown/disabled close) → Task 3 Step 6 + Task 4 Step 3 guard; state dir gitignored → Task 4. Covered.
- **Interface discovery:** Task 3 Step 1 captures the real `workmux list` / `gh` shapes before the parser is written — the one genuine unknown, handled as an explicit step rather than a guess.
- **Consistency:** row key `repo:handle` and the `__gather`/`__close`/`__mergeinto`/`__logline`/`__rowtest` sub-command hooks are used consistently across Tasks 3–5; `pr_state` returns `STATE\tCI\tNUMBER` everywhere.
- **YAGNI:** no daemon, no TUI framework, no cross-repo memory aggregation; each piece independently committable and reversible.

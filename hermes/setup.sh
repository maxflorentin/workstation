#!/usr/bin/env bash
# hermes/setup.sh — codify the hardened Hermes execution sandbox.
#
# Idempotent: safe to run repeatedly. It provisions ONLY code + config.
# Secrets (the agent private key, .env, provider tokens) live under
# ~/.hermes and are NEVER stored in this repo.
#
# What it does:
#   1. Generate a dedicated agent SSH key (if missing) in ~/.hermes/ssh
#   2. Build the hermes-agent-ssh sandbox image (base + openssh-client)
#   3. Point Hermes' terminal backend at Docker and mount the key read-only
#   4. Restart the gateway so the new config takes effect
#
# Usage:  ./setup.sh [--with-poc]
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SSH_DIR="$HERMES_HOME/ssh"
KEY="$SSH_DIR/hermes_id_ed25519"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_BIN="$(command -v hermes || echo "$HOME/.local/bin/hermes")"

# Use the Hermes venv python (guaranteed to have PyYAML); fall back to python3.
PY="$HERMES_HOME/hermes-agent/venv/bin/python"
[ -x "$PY" ] || PY="python3"

echo "==> 1. Dedicated agent SSH key"
mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "hermes-agent@$(hostname)" -q
  echo "    generated $KEY"
else
  echo "    exists, keeping $KEY"
fi
chmod 600 "$KEY"; chmod 644 "$KEY.pub"

echo "==> 1b. SSH client inventory + agent policy"
# Inventory: friendly client names the agent resolves (ssh -F .../config <name>).
# Real file is gitignored; seed it from the template on first run.
if [ ! -f "$SSH_DIR/config" ]; then
  cp "$HERE/ssh/config.example" "$SSH_DIR/config"
  chmod 600 "$SSH_DIR/config"
  echo "    seeded $SSH_DIR/config (add your clients there)"
else
  echo "    keeping existing $SSH_DIR/config"
fi
# Agent operating policy / persona, versioned in this repo and symlinked in.
if [ -f "$HERMES_HOME/SOUL.md" ] && [ ! -L "$HERMES_HOME/SOUL.md" ]; then
  mv "$HERMES_HOME/SOUL.md" "$HERMES_HOME/SOUL.md.bak-setup-$$"
fi
ln -sfn "$HERE/SOUL.md" "$HERMES_HOME/SOUL.md"
echo "    linked SOUL.md -> $HERE/SOUL.md"

echo "==> 2. Build sandbox image (hermes-agent-ssh:latest)"
# Legacy builder: avoids BuildKit's registry metadata lookup, which fails on
# hosts where Docker DNS is routed through Tailscale MagicDNS.
DOCKER_BUILDKIT=0 docker build -t hermes-agent-ssh:latest "$HERE/docker/agent-ssh"

echo "==> 3. Apply hardened terminal config"
CFG="$("$HERMES_BIN" config path)"
cp "$CFG" "$CFG.bak-setup-$$"   # safety backup before any rewrite
"$PY" - "$CFG" "$SSH_DIR" <<'PYEOF'
import sys, yaml
cfg_path, ssh_dir = sys.argv[1], sys.argv[2]
mount = f"{ssh_dir}:/opt/hermes-ssh:ro"
with open(cfg_path) as f:
    cfg = yaml.safe_load(f) or {}
t = cfg.setdefault("terminal", {})
changed = False
def setk(k, v):
    global changed
    if t.get(k) != v:
        t[k] = v; changed = True
setk("backend", "docker")
setk("docker_image", "hermes-agent-ssh:latest")
vols = t.get("docker_volumes")
if not isinstance(vols, list):
    vols = []
if mount not in vols:
    vols.append(mount); t["docker_volumes"] = vols; changed = True
if changed:
    with open(cfg_path, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True)
    print("    config updated")
else:
    print("    config already hardened")
PYEOF

echo "==> 4. Restart gateway"
"$HERMES_BIN" gateway restart

if [ "${1:-}" = "--with-poc" ]; then
  echo "==> 5. Proof-of-concept client"
  "$HERE/poc.sh" up
fi

echo "Done."

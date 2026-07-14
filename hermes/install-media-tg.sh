#!/usr/bin/env bash
# Install the full "native media over Telegram" integration:
#
#   1. media-add with artist (Lidarr) support + dispatcher whitelist,
#      via hermes-media-setup.sh (idempotent, also refreshes /etc/media-add.env
#      so it now includes LIDARR_API_KEY)
#   2. the updated /media skill (artist verbs), via hermes-media-skill.sh
#   3. the media-tg deterministic plugin (tappable /m /mm /mst commands)
#   4. SOUL.md media section (symlinked installs pick it up from the repo;
#      copied installs get a fresh copy)
#   5. gateway restart
#
#   sudo bash ~/.dotfiles/hermes/install-media-tg.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }

OP="${SUDO_USER:-max}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA="/home/$OP/.dotfiles/linux/media"
HU="${HERMES_USER:-hermes}"
HU_HOME="$(getent passwd "$HU" | cut -d: -f6)"
[ -n "$HU_HOME" ] || { echo "user $HU does not exist"; exit 1; }

echo "==> 1. media-add + dispatcher + /etc/media-add.env (idempotent setup)"
bash "$MEDIA/hermes-media-setup.sh"

echo "==> 2. /media skill (artist verbs)"
bash "$MEDIA/hermes-media-skill.sh"

echo "==> 3. media-tg plugin"
pdir="$HU_HOME/.hermes/plugins/media-tg"
install -d -o "$HU" -g "$HU" "$HU_HOME/.hermes/plugins" "$pdir"
install -m 0644 -o "$HU" -g "$HU" "$HERE/plugins/media-tg/plugin.yaml" "$pdir/plugin.yaml"
install -m 0644 -o "$HU" -g "$HU" "$HERE/plugins/media-tg/__init__.py" "$pdir/__init__.py"
echo "    installed $pdir"

echo "==> 3b. Enable media-tg in the gateway config (plugins.enabled)"
runuser -u "$HU" -- bash -lc '
PY="$HOME/.hermes/hermes-agent/venv/bin/python"; [ -x "$PY" ] || PY=python3
"$PY" - "$(hermes config path)" <<PYEOF
import sys, yaml
p = sys.argv[1]
with open(p) as f:
    cfg = yaml.safe_load(f) or {}
en = cfg.setdefault("plugins", {}).setdefault("enabled", [])
if "media-tg" in en:
    print("    already enabled")
else:
    en.append("media-tg")
    with open(p, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True)
    print("    enabled media-tg")
PYEOF'

echo "==> 4. SOUL.md"
soul="$HU_HOME/.hermes/SOUL.md"
if [ -L "$soul" ]; then
    echo "    symlink -> $(readlink "$soul") (repo edit is already live)"
else
    install -m 0644 -o "$HU" -g "$HU" "$HERE/SOUL.md" "$soul"
    echo "    copied fresh SOUL.md"
fi

echo "==> 5. Restart gateway"
runuser -u "$HU" -- bash -lc 'hermes gateway restart' \
    || echo "    NOTE: restart failed — restart the gateway manually"

echo
echo "Done. Test from Telegram:"
echo "  /m severance          (tappable series/movie results)"
echo "  /mm el mato           (tappable artist results)"
echo "  /mst                  (download status)"
echo "  natural language: \"bajame la peli Perfect Days\" (model path, no /media needed)"

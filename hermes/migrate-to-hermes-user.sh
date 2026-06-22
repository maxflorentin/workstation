#!/usr/bin/env bash
# Phase 2: provision Hermes under the unprivileged `hermes` user from the
# existing operator install, then restore config/keys via the native backup.
# The venv is rebuilt (venvs hardcode absolute paths); only source is copied.
#
# Prereq:  as the operator,  hermes backup -o /tmp/hermes-migrate.zip
# Run:     sudo bash ~/.dotfiles/hermes/migrate-to-hermes-user.sh
set -euo pipefail

SRC_USER="${SRC_USER:-max}"
U="${HERMES_USER:-hermes}"
SRC="/home/$SRC_USER/.hermes"
DST="/home/$U/.hermes"
BACKUP="${BACKUP:-/tmp/hermes-migrate.zip}"
UID_H="$(id -u "$U")"
RUNDIR="/run/user/$UID_H"

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
[ -f "$BACKUP" ] || { echo "missing $BACKUP — run 'hermes backup -o $BACKUP' as $SRC_USER"; exit 1; }

run_as() { runuser -u "$U" -- env HOME="/home/$U" XDG_RUNTIME_DIR="$RUNDIR" \
  PATH="/home/$U/.local/bin:/usr/bin:/usr/sbin:/sbin:/bin" "$@"; }

echo "==> 1. uv for $U"
install -d -o "$U" -g "$U" -m755 "/home/$U/.local/bin"
install -o "$U" -g "$U" -m755 "/home/$SRC_USER/.local/bin/uv" "/home/$U/.local/bin/uv"

echo "==> 2. copy hermes-agent source (no venv/.git/pycache)"
install -d -o "$U" -g "$U" -m700 "$DST"
rsync -a --delete \
  --exclude venv --exclude .git --exclude __pycache__ --exclude '*.pyc' \
  "$SRC/hermes-agent/" "$DST/hermes-agent/"
chown -R "$U:$U" "$DST/hermes-agent"

echo "==> 3. build venv as $U (uv pip install -e; network needed, a few min)"
# setup-hermes.sh returns non-zero when the trailing setup wizard is declined
# (EOF from </dev/null); the venv build is what matters, so tolerate it and
# verify the CLI landed instead.
run_as bash -c 'cd ~/.hermes/hermes-agent && ./setup-hermes.sh < /dev/null' || true
[ -x "/home/$U/.local/bin/hermes" ] || { echo "hermes CLI not installed under $U — setup-hermes.sh failed for real"; exit 1; }

echo "==> 4. restore config/keys/sessions from backup"
run_as "/home/$U/.local/bin/hermes" import "$BACKUP" --force

echo "==> 5. critical secrets safety-copy (only if import missed them)"
for f in .env auth.json; do
  [ -f "$DST/$f" ] || { cp -a "$SRC/$f" "$DST/$f" 2>/dev/null && echo "    copied $f"; }
done
[ -d "$DST/ssh" ] || { cp -a "$SRC/ssh" "$DST/ssh" && echo "    copied ssh/"; }
chown -R "$U:$U" "$DST"
chmod 700 "$DST/ssh" 2>/dev/null || true; chmod 600 "$DST"/ssh/hermes_* 2>/dev/null || true

echo "==> 6. repoint host paths in config ($SRC -> $DST)"
sed -i "s#/home/$SRC_USER/.hermes/ssh#/home/$U/.hermes/ssh#g" "$DST/config.yaml"

echo
echo "==> verify"
run_as "/home/$U/.local/bin/hermes" --version 2>&1 | head -1 || true
echo "config.yaml docker_volumes:"; grep -A1 docker_volumes "$DST/config.yaml" | head -2
echo "ssh keys present:"; ls "$DST"/ssh/*.pub 2>/dev/null | wc -l
echo ".env present: $([ -f "$DST/.env" ] && echo yes || echo NO)"
echo
echo "OK — Hermes provisioned under $U. Next: build the sandbox image in rootless docker, then the service + cutover."

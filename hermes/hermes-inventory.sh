#!/usr/bin/env bash
# Read-only snapshot of the live Hermes install (user `hermes`), secrets redacted.
#   sudo bash scripts/hermes-inventory.sh [output-file]
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }

OP="${SUDO_USER:-max}"
OUT="${1:-/home/$OP/hermes-inventory.txt}"
HU="${HERMES_USER:-hermes}"
HU_HOME="$(getent passwd "$HU" | cut -d: -f6)"
HU_UID="$(id -u "$HU")"
H="$HU_HOME/.hermes"
PY="$H/hermes-agent/venv/bin/python"

as_hermes() {
    runuser -u "$HU" -- env HOME="$HU_HOME" XDG_RUNTIME_DIR="/run/user/$HU_UID" \
        PATH="$HU_HOME/.local/bin:$H/hermes-agent/venv/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}

redact_yaml() {
    "$PY" - "$1" <<'PYEOF'
import re, sys, yaml
SECRET = re.compile(r"(token|key|secret|password|passwd|auth|cookie|credential)", re.I)
def walk(v):
    if isinstance(v, dict):
        return {k: ("<redacted>" if SECRET.search(str(k)) and isinstance(val, (str, int)) else walk(val))
                for k, val in v.items()}
    if isinstance(v, list):
        return [walk(x) for x in v]
    return v
with open(sys.argv[1]) as f:
    print(yaml.safe_dump(walk(yaml.safe_load(f) or {}), sort_keys=False, allow_unicode=True))
PYEOF
}

{
    echo "# Hermes inventory — $(date -Is)"
    echo
    echo "## version";        as_hermes hermes --version 2>&1 || true
    echo; echo "## git HEAD";  git -C "$H/hermes-agent" log -1 --format='%h %ad %s' --date=short 2>&1 || true
    echo; echo "## profiles"; as_hermes hermes profile list 2>&1 || true
    echo; echo "## profile dirs"; ls -la "$H/profiles" 2>/dev/null || echo "(none)"
    echo; echo "## systemd --user units"
    as_hermes systemctl --user list-units --all --no-pager 'hermes*' 2>&1 || true
    echo; echo "## .env variable NAMES only"
    grep -Eo '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$H/.env" 2>/dev/null \
        | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/=$//' | sort || true
    echo; echo "## config.yaml (redacted)"; redact_yaml "$H/config.yaml" || true
    echo; echo "## skills"; find "$H/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | sed "s|$H/skills/||" | sort
    echo; echo "## plugins"; ls -la "$H/plugins" 2>/dev/null || true
    echo; echo "## cron"; as_hermes hermes cron list 2>&1 || ls -la "$H/cron" 2>/dev/null || true
    echo; echo "## SOUL.md"; ls -la "$H/SOUL.md" 2>/dev/null || true
    echo; echo "## browser config"; as_hermes hermes config get browser 2>&1 || true
} > "$OUT" 2>&1

chown "$OP:$OP" "$OUT"
chmod 600 "$OUT"
echo "wrote $OUT"

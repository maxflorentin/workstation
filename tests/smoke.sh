#!/bin/bash

# Fast repo smoke tests. No network, no SSH, no sudo.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

ok() { printf 'ok   %s\n' "$*"; }
fail() { printf 'fail %s\n' "$*"; FAIL=$((FAIL + 1)); }

check_bash() {
    local file="$1"
    if bash -n "$file"; then
        ok "bash -n $file"
    else
        fail "bash -n $file"
    fi
}

echo "workstation smoke"
echo "  root: $ROOT"
echo ""

check_bash "$ROOT/install"
check_bash "$ROOT/install-corporate"
check_bash "$ROOT/linux/work"
check_bash "$ROOT/linux/bootstrap.sh"
check_bash "$ROOT/linux/migrate.sh"
check_bash "$ROOT/linux/tmux-layout"
check_bash "$ROOT/linux/tailscale-client-setup.sh"
check_bash "$ROOT/scripts/envy/envy-doctor"
check_bash "$ROOT/scripts/work-tracker"
check_bash "$ROOT/workstation/workstation"
check_bash "$ROOT/workstation/doctor"

echo ""
if "$ROOT/workstation/workstation" help >/dev/null; then
    ok "workstation help"
else
    fail "workstation help"
fi

if "$ROOT/linux/work" >/dev/null; then
    ok "work help"
else
    fail "work help"
fi

if "$ROOT/scripts/work-tracker" >/dev/null; then
    ok "work-tracker help"
else
    fail "work-tracker help"
fi

if "$ROOT/scripts/envy/envy-doctor" --definitely-not-a-real-context >/dev/null 2>&1; then
    fail "envy-doctor missing context should fail"
else
    ok "envy-doctor missing context fails"
fi

tmp_log="$(mktemp "${TMPDIR:-/tmp}/work-tracker-smoke.XXXXXX")"
cat > "$tmp_log" <<'EOF'
timestamp	event	client	project	source
100	start	acme	app	mac
400	tick	acme	app	pi
700	tick	acme	app	pi
3700	stop	acme	app	mac
EOF

if WORK_TRACKER_LOG="$tmp_log" "$ROOT/scripts/work-tracker" report --all | grep -q 'acme/app'; then
    ok "work-tracker report fixture"
else
    fail "work-tracker report fixture"
fi
rm -f "$tmp_log"

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "smoke failed: $FAIL failure(s)"
    exit 1
fi

echo "smoke passed"

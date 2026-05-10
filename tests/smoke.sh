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

check_output_contains() {
    local name="$1"
    local output="$2"
    local expected="$3"

    if [[ "$output" == *"$expected"* ]]; then
        ok "$name"
    else
        fail "$name"
    fi
}

echo "workstation smoke"
echo "  root: $ROOT"
echo ""

check_bash "$ROOT/install"
check_bash "$ROOT/install-corporate"
check_bash "$ROOT/linux/work"
check_bash "$ROOT/linux/bootstrap.sh"
check_bash "$ROOT/linux/tmux-layout"
check_bash "$ROOT/linux/tailscale-client-setup.sh"
check_bash "$ROOT/scripts/brew-sync"
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

work_help="$("$ROOT/linux/work")"
if [ -n "$work_help" ]; then
    ok "work help"
else
    fail "work help"
fi
check_output_contains "work help documents connect browse flag" "$work_help" "work connect [--browse]"
check_output_contains "work help documents clients" "$work_help" "work clients"
check_output_contains "work help documents onboard" "$work_help" "work onboard <client>"
check_output_contains "work help documents clientrc init" "$work_help" "work clientrc-init [--force] <client>"
check_output_contains "work help documents clientrc doctor" "$work_help" "work clientrc-doctor <client>"
check_output_contains "work help documents client profile" "$work_help" "work client-profile <client>"
check_output_contains "work help documents tailscale doctor scope" "$work_help" "Check personal path; with client, also secondary"
check_output_contains "work help documents browse status flag" "$work_help" "work browse [--status] <client>"
check_output_contains "work help documents connect browse env" "$work_help" "WORK_CONNECT_BROWSE"
check_output_contains "work help documents legacy commands" "$work_help" "work legacy"

connect_usage="$("$ROOT/linux/work" connect --browse 2>&1)"
check_output_contains "work connect --browse requires client" "$connect_usage" "Usage: work connect [--browse] <client> [project]"

browse_usage="$("$ROOT/linux/work" browse --status 2>&1)"
check_output_contains "work browse --status requires client" "$browse_usage" "Usage: work browse --status <client>"

clientrc_usage="$("$ROOT/linux/work" clientrc-init 2>&1)"
check_output_contains "work clientrc-init requires client" "$clientrc_usage" "Usage: work clientrc-init [--force] <client>"

clientrc_doctor_usage="$("$ROOT/linux/work" clientrc-doctor 2>&1)"
check_output_contains "work clientrc-doctor requires client" "$clientrc_doctor_usage" "Usage: work clientrc-doctor <client>"

client_profile_usage="$("$ROOT/linux/work" client-profile 2>&1)"
check_output_contains "work client-profile requires client" "$client_profile_usage" "Usage: work client-profile <client>"

onboard_usage="$("$ROOT/linux/work" onboard 2>&1)"
check_output_contains "work onboard requires client" "$onboard_usage" "Usage: work onboard <client>"

onboard_output="$("$ROOT/linux/work" onboard acme 2>&1)"
check_output_contains "work onboard prints checklist" "$onboard_output" "client onboarding checklist"
check_output_contains "work onboard includes clientrc doctor" "$onboard_output" "work clientrc-doctor acme"
check_output_contains "work onboard includes client profile" "$onboard_output" "work client-profile acme"
check_output_contains "work onboard includes compliance boundary" "$onboard_output" "must not scan /home"

legacy_help="$("$ROOT/linux/work" legacy)"
check_output_contains "work legacy documents vpn-up" "$legacy_help" "work vpn-up <client>"
check_output_contains "work legacy points to tailscale" "$legacy_help" "work tailscale-setup <client>"

if [ -f "$ROOT/templates/clientrc.example" ] && grep -q '<client>' "$ROOT/templates/clientrc.example"; then
    ok "clientrc template exists and stays placeholder-based"
else
    fail "clientrc template exists and stays placeholder-based"
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

tmp_data="$(mktemp -d "${TMPDIR:-/tmp}/work-tracker-data.XXXXXX")"
XDG_DATA_HOME="$tmp_data" "$ROOT/scripts/work-tracker" start acme app mac
printf '%s\ttick\tacme\tapp\tworkstation\n' "$(date +%s)" >> "$tmp_data/work-tracker/log.tsv"
XDG_DATA_HOME="$tmp_data" "$ROOT/scripts/work-tracker" stop acme app mac
if grep -q $'\tstop\tacme\tapp\tmac$' "$tmp_data/work-tracker/log.tsv"; then
    ok "work-tracker stop after tick"
else
    fail "work-tracker stop after tick"
fi
rm -rf "$tmp_data"

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "smoke failed: $FAIL failure(s)"
    exit 1
fi

echo "smoke passed"

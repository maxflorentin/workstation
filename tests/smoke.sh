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

if [ -f "$ROOT/macos/Brewfile.workstation" ] && grep -q 'brew "shellcheck"' "$ROOT/macos/Brewfile.workstation"; then
    ok "workstation Brewfile profile exists"
else
    fail "workstation Brewfile profile exists"
fi

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
check_output_contains "work help documents tracker doctor" "$work_help" "work tracker-doctor [client]"
check_output_contains "work help documents tracker repair" "$work_help" "work tracker-repair <client|--all>"
check_output_contains "work help documents config backup dry run" "$work_help" "work config-backup [--dry-run]"
check_output_contains "work help documents legacy commands" "$work_help" "work legacy"

brew_sync_help="$("$ROOT/scripts/brew-sync" --help)"
check_output_contains "brew-sync documents profile flag" "$brew_sync_help" "brew-sync --profile workstation"

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

config_backup_usage="$("$ROOT/linux/work" config-backup 2>&1)"
check_output_contains "work config-backup requires args" "$config_backup_usage" "Usage: work config-backup [--dry-run] <client> <dest-dir> <age-recipient>"

tmp_backup_target="$(mktemp -d "${TMPDIR:-/tmp}/work-config-backup-target.XXXXXX")"
config_backup_remote_guard="$("$ROOT/linux/work" config-backup acme "$tmp_backup_target" 'age1testrecipient' 2>&1 || true)"
if printf '%s\n' "$config_backup_remote_guard" | grep -qE 'config-backup must run on the workstation|config-backup requires sudo'; then
    ok "work config-backup refuses unsafe local context"
else
    fail "work config-backup refuses unsafe local context"
fi
config_backup_dry_run_guard="$("$ROOT/linux/work" config-backup --dry-run acme "$tmp_backup_target" 'age1testrecipient' 2>&1 || true)"
if printf '%s\n' "$config_backup_dry_run_guard" | grep -qE 'config-backup must run on the workstation|config-backup requires sudo'; then
    ok "work config-backup dry-run refuses unsafe local context"
else
    fail "work config-backup dry-run refuses unsafe local context"
fi
rm -rf "$tmp_backup_target"

onboard_usage="$("$ROOT/linux/work" onboard 2>&1)"
check_output_contains "work onboard requires client" "$onboard_usage" "Usage: work onboard <client>"

onboard_output="$("$ROOT/linux/work" onboard acme 2>&1)"
check_output_contains "work onboard prints checklist" "$onboard_output" "client onboarding checklist"
check_output_contains "work onboard includes clientrc doctor" "$onboard_output" "work clientrc-doctor acme"
check_output_contains "work onboard includes client profile" "$onboard_output" "work client-profile acme"
check_output_contains "work onboard includes tracker repair" "$onboard_output" "work tracker-repair acme"
check_output_contains "work onboard includes compliance boundary" "$onboard_output" "must not scan /home"
check_output_contains "work onboard includes config backup dry run" "$onboard_output" "work config-backup --dry-run acme"
check_output_contains "work onboard includes restore drill" "$onboard_output" "restore drill"

tracker_repair_usage="$("$ROOT/linux/work" tracker-repair 2>&1)"
check_output_contains "work tracker-repair requires client" "$tracker_repair_usage" "Usage: work tracker-repair <client|--all>"

tmp_bin="$(mktemp -d "${TMPDIR:-/tmp}/work-smoke-bin.XXXXXX")"
cat > "$tmp_bin/ssh" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -T|-t|-tt) shift ;;
        -o) shift 2 ;;
        *@*) shift ;;
        *) break ;;
    esac
done
eval "$*"
EOF
cat > "$tmp_bin/sudo" <<'EOF'
#!/bin/sh
if [ "$1" = "-n" ] && [ "$2" = "true" ]; then
    exit 1
fi
exit 1
EOF
chmod +x "$tmp_bin/ssh" "$tmp_bin/sudo"
tracker_limited="$(
    PATH="$tmp_bin:$PATH" WORKSTATION_HOST=smoke-host WORKSTATION_USER=max "$ROOT/linux/work" tracker-doctor acme 2>&1 || true
)"
check_output_contains "work tracker-doctor avoids sudo prompt" "$tracker_limited" "workstation sudo unavailable"
check_output_contains "work tracker-doctor suggests sudo command" "$tracker_limited" "sudo ~/.local/bin/work tracker-doctor acme"
tracker_repair_limited="$(
    PATH="$tmp_bin:$PATH" WORKSTATION_HOST=smoke-host WORKSTATION_USER=max "$ROOT/linux/work" tracker-repair acme 2>&1 || true
)"
check_output_contains "work tracker-repair avoids sudo prompt" "$tracker_repair_limited" "tracker-repair requires sudo on the workstation"
check_output_contains "work tracker-repair suggests sudo command" "$tracker_repair_limited" "sudo ~/.local/bin/work tracker-repair acme"
user_create_limited="$(
    PATH="$tmp_bin:$PATH" WORKSTATION_HOST=smoke-host WORKSTATION_USER=max "$ROOT/linux/work" user-create acme 2>&1 || true
)"
check_output_contains "work user-create avoids sudo prompt" "$user_create_limited" "user-create requires sudo on the workstation"
check_output_contains "work user-create suggests sudo command" "$user_create_limited" "sudo ~/.local/bin/work user-create acme"
clientrc_init_limited="$(
    PATH="$tmp_bin:$PATH" WORKSTATION_HOST=smoke-host WORKSTATION_USER=max "$ROOT/linux/work" clientrc-init acme 2>&1 || true
)"
check_output_contains "work clientrc-init avoids sudo prompt" "$clientrc_init_limited" "clientrc-init requires sudo on the workstation"
check_output_contains "work clientrc-init suggests sudo command" "$clientrc_init_limited" "sudo ~/.local/bin/work clientrc-init acme"
rm -rf "$tmp_bin"

report_missing_tracker="$(
    PATH="/usr/bin:/bin" "$ROOT/linux/work" report 2>&1 || true
)"
check_output_contains "work report explains missing local tracker" "$report_missing_tracker" "work report requires work-tracker"

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

tracker_crons="$("$ROOT/scripts/work-tracker" cron-lines /tmp/work-tracker)"
check_output_contains "work-tracker cron lines include pulse" "$tracker_crons" "/tmp/work-tracker pulse"
check_output_contains "work-tracker cron lines include monthly save" "$tracker_crons" "/tmp/work-tracker monthly-save"

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
not-a-ts	tick	broken	app	pi
900	tick	too	few
EOF

if WORK_TRACKER_LOG="$tmp_log" "$ROOT/scripts/work-tracker" report --all | grep -q 'acme/app'; then
    ok "work-tracker report fixture"
else
    fail "work-tracker report fixture"
fi
if WORK_TRACKER_LOG="$tmp_log" "$ROOT/scripts/work-tracker" report --all | grep -q 'broken'; then
    fail "work-tracker report ignores malformed rows"
else
    ok "work-tracker report ignores malformed rows"
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

tmp_data="$(mktemp -d "${TMPDIR:-/tmp}/work-tracker-data.XXXXXX")"
XDG_DATA_HOME="$tmp_data" "$ROOT/scripts/work-tracker" start acme $'bad\tname' $'mac\nbook'
if awk -F'\t' 'NR==2 && NF==5 && $4=="bad name" && $5=="mac book" { ok=1 } END { exit ok ? 0 : 1 }' "$tmp_data/work-tracker/log.tsv"; then
    ok "work-tracker sanitizes tsv fields"
else
    fail "work-tracker sanitizes tsv fields"
fi
rm -rf "$tmp_data"

tmp_data="$(mktemp -d "${TMPDIR:-/tmp}/work-tracker-data.XXXXXX")"
tmp_bin="$(mktemp -d "${TMPDIR:-/tmp}/work-tracker-bin.XXXXXX")"
now="$(date +%s)"
cat > "$tmp_bin/tmux" <<EOF
#!/bin/sh
printf 'app %s\n' "$now"
EOF
chmod +x "$tmp_bin/tmux"
PATH="$tmp_bin:$PATH" USER=acme XDG_DATA_HOME="$tmp_data" WORK_TRACKER_SOURCE=workstation WORK_TRACKER_NOW="$now" "$ROOT/scripts/work-tracker" pulse
PATH="$tmp_bin:$PATH" USER=acme XDG_DATA_HOME="$tmp_data" WORK_TRACKER_SOURCE=workstation WORK_TRACKER_NOW="$now" "$ROOT/scripts/work-tracker" pulse
tick_count="$(awk -F'\t' '$2=="tick" {n++} END {print n+0}' "$tmp_data/work-tracker/log.tsv")"
if [ "$tick_count" = "1" ]; then
    ok "work-tracker pulse deduplicates interval ticks"
else
    fail "work-tracker pulse deduplicates interval ticks"
fi
rm -rf "$tmp_data" "$tmp_bin"

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "smoke failed: $FAIL failure(s)"
    exit 1
fi

echo "smoke passed"

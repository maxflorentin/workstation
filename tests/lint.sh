#!/bin/bash

# Repo lint checks. No network, no SSH, no sudo.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

ok() { printf 'ok   %s\n' "$*"; }
fail() { printf 'fail %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "workstation lint"
echo "  root: $ROOT"
echo ""

if ! command -v shellcheck >/dev/null 2>&1; then
    fail "shellcheck missing"
else
    shellcheck -S warning \
        "$ROOT/install" \
        "$ROOT/install-corporate" \
        "$ROOT/linux/bootstrap.sh" \
        "$ROOT/linux/ecryptfs-auto-mount" \
        "$ROOT/linux/tailscale-client-setup.sh" \
        "$ROOT/linux/media/media" \
        "$ROOT/linux/media/hermes-media-dispatch" \
        "$ROOT/linux/media/hermes-media-setup.sh" \
        "$ROOT/linux/media/hermes-media-skill.sh" \
        "$ROOT/linux/tmux-layout" \
        "$ROOT/linux/work" \
        "$ROOT/macos/defaults.sh" \
        "$ROOT/macos/fresh.sh" \
        "$ROOT/scripts/brew-sync" \
        "$ROOT/scripts/envy/envy-doctor" \
        "$ROOT/scripts/work-tracker" \
        "$ROOT/tests/smoke.sh" \
        "$ROOT/workstation/bootstrap" \
        "$ROOT/workstation/doctor" \
        "$ROOT/workstation/tailscale-client-setup" \
        "$ROOT/workstation/tmux-layout" \
        "$ROOT/workstation/workstation"
    if [ "$?" -eq 0 ]; then
        ok "shellcheck warning/error lint"
    else
        fail "shellcheck warning/error lint"
    fi
fi

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "git diff --check skipped outside git worktree"
elif git -C "$ROOT" diff --check -- . ':(exclude).claude/*' >/dev/null; then
    ok "git diff --check"
else
    fail "git diff --check"
fi

NEXTDNS_SAMPLE="7eb5""e4"
TAILSCALE_IPV4_SAMPLE="100\\.72"\\.6\\.32
TAILSCALE_IPV6_SAMPLE="fd7a:""115c"
SANITIZED_PATTERNS="$NEXTDNS_SAMPLE|$TAILSCALE_IPV4_SAMPLE|$TAILSCALE_IPV6_SAMPLE"
if rg -n "$SANITIZED_PATTERNS" \
    "$ROOT/README.md" "$ROOT/docs" "$ROOT/linux" "$ROOT/scripts" "$ROOT/templates" "$ROOT/tmux" "$ROOT/workstation" "$ROOT/tests" >/dev/null; then
    fail "sanitization scan"
else
    ok "sanitization scan"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "lint failed: $FAIL failure(s)"
    exit 1
fi

echo "lint passed"

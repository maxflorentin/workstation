#!/usr/bin/env bash
# Install or update a Hermes profile distribution into the live Hermes (user `hermes`),
# including the envy context its config points at. Extra files are copied into the
# profile, e.g. shared rules that live outside it.
# Leaves the default profile (infra/media/workmux on Telegram) untouched.
#   sudo bash hermes/install-profile.sh <profile-dir> [extra-file...]
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0 <profile-dir> [extra-file...]"; exit 1; }
SRC="$(realpath "${1:?usage: $0 <profile-dir> [extra-file...]}")"
shift
[ -f "$SRC/distribution.yaml" ] || { echo "no distribution.yaml in $SRC"; exit 1; }
NAME="$(sed -n 's/^name:[[:space:]]*//p' "$SRC/distribution.yaml" | head -1)"

OP="${SUDO_USER:-max}"
OP_HOME="$(getent passwd "$OP" | cut -d: -f6)"
HU="${HERMES_USER:-hermes}"
HU_HOME="$(getent passwd "$HU" | cut -d: -f6)"
HU_UID="$(id -u "$HU")"
as_hermes() {
    runuser -u "$HU" -- env HOME="$HU_HOME" XDG_RUNTIME_DIR="/run/user/$HU_UID" \
        PATH="$HU_HOME/.local/bin:$HU_HOME/.hermes/hermes-agent/venv/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}

# The hermes user can't read the operator's home, so stage a copy it owns.
STAGE="$(mktemp -d /tmp/hermes-profile.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cp -a "$SRC/." "$STAGE/"
for extra in "$@"; do
    cp "$extra" "$STAGE/"
done
chown -R "$HU:$HU" "$STAGE"

ENVY_CTX="$(sed -n 's/.*\.envy\/keys\/\([^.]*\)\.key.*/\1/p' "$SRC/config.yaml" | head -1)"
if [ -n "$ENVY_CTX" ]; then
    as_hermes age --version >/dev/null || { echo "age is not on the $HU user's PATH"; exit 1; }
    echo "==> copying envy context $ENVY_CTX"
    install -d -m 0700 -o "$HU" -g "$HU" "$HU_HOME/.envy" "$HU_HOME/.envy/keys"
    install -m 0600 -o "$HU" -g "$HU" "$OP_HOME/.envy/keys/$ENVY_CTX.key" "$HU_HOME/.envy/keys/$ENVY_CTX.key"
    install -m 0600 -o "$HU" -g "$HU" "$OP_HOME/.envy/$ENVY_CTX.envy.age" "$HU_HOME/.envy/$ENVY_CTX.envy.age"
fi

FORCE=""
if as_hermes hermes profile list 2>/dev/null | grep -qw "$NAME"; then
    FORCE="--force"   # update in place; memories, sessions and .env are preserved
fi

echo "==> installing $NAME from $SRC ${FORCE:+(update)}"
as_hermes hermes profile install "$STAGE" --name "$NAME" --alias --yes $FORCE

PDIR="$HU_HOME/.hermes/profiles/$NAME"
if [ ! -f "$PDIR/.env" ]; then
    cat <<EOF

==> $NAME installed, gateway NOT started (no .env yet).
    1. Create a new bot with @BotFather (do not reuse the infra bot's token).
    2. sudo -u $HU cp $PDIR/.env.EXAMPLE $PDIR/.env && sudo -u $HU \$EDITOR $PDIR/.env
       (TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS)
    3. Re-run this script to install and start the gateway.
EOF
    exit 0
fi

echo "==> installing and (re)starting the $NAME gateway"
as_hermes hermes -p "$NAME" gateway install
as_hermes hermes -p "$NAME" gateway restart || as_hermes hermes -p "$NAME" gateway start
as_hermes hermes -p "$NAME" gateway status || true

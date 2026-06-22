#!/usr/bin/env bash
# Phase 1 of running the Hermes gateway under an unprivileged user: bring up
# rootless Docker for the `hermes` service user, so the gateway process cannot
# escalate to root via the system docker socket (it never joins the `docker`
# group). Idempotent.
#
#   sudo bash ~/.dotfiles/hermes/rootless-gateway-setup.sh
set -euo pipefail

U="${HERMES_USER:-hermes}"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }
id "$U" >/dev/null 2>&1 || { echo "user $U does not exist"; exit 1; }

UID_H="$(id -u "$U")"
RUNDIR="/run/user/$UID_H"
SOCK="$RUNDIR/docker.sock"

# Run a command as the service user with a proper user-session environment.
run_as() {
  runuser -u "$U" -- env \
    HOME="/home/$U" \
    XDG_RUNTIME_DIR="$RUNDIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNDIR/bus" \
    PATH=/usr/bin:/usr/sbin:/sbin:/bin \
    "$@"
}

[ -d "$RUNDIR" ] || { echo "no $RUNDIR — enable linger: sudo loginctl enable-linger $U"; exit 1; }
command -v newuidmap >/dev/null || { echo "missing uidmap (sudo apt-get install uidmap)"; exit 1; }

echo "==> installing rootless docker for $U (idempotent)"
run_as dockerd-rootless-setuptool.sh install --force

echo "==> enabling + starting the rootless docker user service"
run_as systemctl --user enable --now docker

echo "==> waiting for the socket"
for i in $(seq 10); do [ -S "$SOCK" ] && break; sleep 1; done

echo "==> verify"
run_as env DOCKER_HOST="unix://$SOCK" docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}'
echo
echo "OK — rootless docker socket for $U: $SOCK"
echo "Gateway will use:  DOCKER_HOST=unix://$SOCK"

#!/usr/bin/env bash
# hermes/poc.sh — simulated "client server" to test the SSH path end-to-end.
#
# Spins up an isolated sshd container that trusts only the Hermes agent key,
# so you can verify Telegram -> Docker sandbox -> SSH without touching any
# real client or production host.
#
# Usage:  ./poc.sh {up|test|down}
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PUB="$HERMES_HOME/ssh/hermes_id_ed25519.pub"
NAME="hermes-poc-client"

ip_of() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME"; }

case "${1:-up}" in
  up)
    [ -f "$PUB" ] || { echo "missing $PUB — run setup.sh first"; exit 1; }
    cp "$PUB" "$HERE/docker/poc-client/hermes_id_ed25519.pub"   # build context (gitignored)
    DOCKER_BUILDKIT=0 docker build -t hermes-poc-client:latest "$HERE/docker/poc-client"
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" hermes-poc-client:latest >/dev/null
    sleep 1
    IP="$(ip_of)"
    echo "POC client up at $IP  (login user: deploy)"
    echo
    echo "From Telegram, send Hermes something like:"
    echo "  Conectate por SSH a deploy@$IP con la llave"
    echo "  /opt/hermes-ssh/hermes_id_ed25519 y decime la version de OS."
    ;;
  test)
    IP="$(ip_of)"
    [ -n "$IP" ] || { echo "POC not running — ./poc.sh up first"; exit 1; }
    docker run --rm -v "$HERMES_HOME/ssh:/opt/hermes-ssh:ro" hermes-agent-ssh:latest \
      ssh -i /opt/hermes-ssh/hermes_id_ed25519 -o IdentitiesOnly=yes \
          -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/kh \
          deploy@"$IP" 'echo "CONNECTED $(whoami)@$(hostname)"; . /etc/os-release; echo "$PRETTY_NAME"'
    ;;
  down)
    docker rm -f "$NAME" >/dev/null 2>&1 && echo "removed $NAME" || echo "not running"
    ;;
  *)
    echo "usage: $0 {up|test|down}"; exit 1 ;;
esac

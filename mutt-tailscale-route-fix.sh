#!/usr/bin/env bash
set -euo pipefail

SERVICE="tailscaled-mutt.service"
UNIT="/etc/systemd/system/${SERVICE}"
SOCKET="/run/tailscale-mutt.sock"
STATE="/var/lib/tailscale-mutt/tailscaled.state"
PORT="41642"
TUN="ts-mutt"
ROLLBACK_PID_FILE="/tmp/mutt-tailscale-route-fix.rollback.pid"
BACKUP=""

log() { printf '\n==> %s\n' "$*"; }
run() { printf '+ %q ' "$@"; printf '\n'; "$@"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo: sudo $0" >&2
    exit 1
  fi
}

schedule_rollback() {
  log "Scheduling rollback in 180 seconds"
  (
    sleep 180
    if systemctl is-active --quiet "$SERVICE"; then
      systemctl stop "$SERVICE" || true
    fi
  ) >/tmp/mutt-tailscale-route-fix.rollback.log 2>&1 &
  echo "$!" > "$ROLLBACK_PID_FILE"
  echo "Rollback PID: $(cat "$ROLLBACK_PID_FILE")"
  echo "If SSH drops, this will stop $SERVICE in 3 minutes."
}

cancel_rollback() {
  if [ -f "$ROLLBACK_PID_FILE" ]; then
    local pid
    pid="$(cat "$ROLLBACK_PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "Canceled rollback PID $pid"
    fi
    rm -f "$ROLLBACK_PID_FILE"
  fi
}

write_unit() {
  if [ -f "$UNIT" ]; then
    BACKUP="${UNIT}.bak.$(date +%Y%m%d-%H%M%S)"
    run cp "$UNIT" "$BACKUP"
    echo "Backup: $BACKUP"
  fi

  log "Writing $UNIT"
  cat > "$UNIT" <<UNIT_EOF
[Unit]
Description=Tailscale secondary - Mutt VPN
After=network-pre.target NetworkManager.service systemd-resolved.service tailscaled.service
Wants=network-pre.target
Requires=tailscaled.service

[Service]
Type=simple
ExecStart=/usr/sbin/tailscaled --state=${STATE} --socket=${SOCKET} --port=${PORT} --tun=${TUN}
Restart=on-failure
RestartSec=5
PrivateDevices=no
NoNewPrivileges=no

[Install]
WantedBy=multi-user.target
UNIT_EOF
}

bring_up_tailscale() {
  log "Reloading and restarting $SERVICE"
  run systemctl daemon-reload
  run systemctl restart "$SERVICE"
  run systemctl status "$SERVICE" --no-pager

  log "Bringing up Mutt Tailscale with routes, DNS disabled, netfilter off"
  run tailscale --socket="$SOCKET" up \
    --hostname="$(hostname)-mutt" \
    --operator="${SUDO_USER:-$USER}" \
    --accept-routes \
    --accept-dns=false \
    --netfilter-mode=off \
    --accept-risk=lose-ssh
}

validate() {
  log "Validating interfaces"
  ip -br link | grep -E 'tailscale|ts-mutt' || true

  log "Validating Mutt tailnet status"
  tailscale --socket="$SOCKET" status | sed -n '1,20p'

  log "Validating private routes in table 52"
  ip route show table 52 | grep -E '172\.31|10\.100' || {
    echo "WARNING: expected private routes were not found in table 52" >&2
    return 1
  }

  log "Validating EKS DNS"
  dig +short 417EA7CB25924281A32A044793B6D08E.gr7.us-east-1.eks.amazonaws.com || true

  log "Validating route to known EKS private IPs"
  ip route get 172.31.0.135 || true
  ip route get 172.31.164.86 || true

  log "Validating TCP connectivity to EKS private IPs"
  nc -vz 172.31.0.135 443
  nc -vz 172.31.164.86 443

  log "Validating EKS API reachability; HTTP 401 is expected"
  curl -k -I --connect-timeout 5 https://417EA7CB25924281A32A044793B6D08E.gr7.us-east-1.eks.amazonaws.com || true

  log "Validating personal Tailscale still responds"
  tailscale status | sed -n '1,10p'
}

main() {
  require_root

  echo "This will change only $SERVICE to use --tun=ts-mutt and then accept Mutt subnet routes."
  echo "Open a second SSH session before continuing."
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted"; exit 1 ;;
  esac

  schedule_rollback
  write_unit
  bring_up_tailscale
  validate
  cancel_rollback

  log "Done"
  echo "If kubectl is configured, now run: kubectl get namespaces"
}

main "$@"

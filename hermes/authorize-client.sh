#!/usr/bin/env bash
# Authorize the Hermes agent's per-client key on a client user account.
#
#   sudo bash ~/.dotfiles/hermes/authorize-client.sh <client>
#
# Idempotent. Appends only — never clobbers the client's existing keys.
# Reaches the client AS that user, so the key lives in the client's own
# authorized_keys and inherits their scoped tailscale/DNS/no-sudo isolation.
set -euo pipefail

client="${1:-}"
[ -n "$client" ] || { echo "usage: sudo bash authorize-client.sh <client>"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "must run as root: sudo bash $0 $client"; exit 1; }

op_home="/home/${SUDO_USER:-max}"
pub="$op_home/.hermes/ssh/hermes_${client}_id_ed25519.pub"
home="/home/${client}"
akf="$home/.ssh/authorized_keys"

[ -f "$pub" ] || { echo "missing pubkey: $pub (generate the per-client key first)"; exit 1; }
[ -d "$home" ] || { echo "no home dir: $home"; exit 1; }

# ecryptfs: sshd can only read authorized_keys while the home is mounted.
if ! mountpoint -q "$home" 2>/dev/null; then
  echo "note: $home is not a mountpoint — if it's an ecryptfs home it must be"
  echo "      mounted (active session) for the agent's key to work."
fi

key="$(cat "$pub")"
install -d -m700 -o "$client" -g "$client" "$home/.ssh"
touch "$akf"
grep -qxF "$key" "$akf" || printf '%s\n' "$key" >> "$akf"
chown "$client:$client" "$akf"
chmod 600 "$akf"

echo "OK-authorized: hermes_${client} key present in $akf"
echo "keys for this agent: $(grep -c "hermes-${client}@" "$akf" || true)"

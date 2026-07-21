#!/bin/bash

# obsidian-setup.sh: Set up Obsidian vault + Syncthing on the workstation
# Run ON the workstation as the operator (max).
#
# What it does:
#   1. Install Syncthing (if missing)
#   2. Enable Syncthing as a user service
#   3. Create vault directory structure
#   4. Create the 'obsidian' client user for Hermes access
#   5. Generate per-client Hermes key for obsidian user
#   6. Print next steps (Syncthing pairing, iCloud migration)
#
# After running this:
#   - Pair Syncthing on the Mac (share vault folder)
#   - Copy vault from iCloud to the synced folder
#   - Run authorize-client.sh obsidian to grant Hermes access
#
# Usage:  sudo bash obsidian-setup.sh

set -euo pipefail

VAULT_DIR="/home/max/obsidian"
CLIENT_USER="obsidian"
HERMES_HOME="/home/max/.hermes"

# Must run as root (needs to create user)
[ "$(id -u)" -eq 0 ] || { echo "must run as root: sudo bash $0"; exit 1; }
OPERATOR="${SUDO_USER:-max}"
OPERATOR_HOME="/home/$OPERATOR"

echo "==> 1. Install Syncthing"
if command -v syncthing &>/dev/null; then
    echo "    already installed: $(syncthing --version | head -1)"
else
    # Official Syncthing APT repo
    curl -fsSL https://syncthing.net/release-key.gpg | gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" \
        > /etc/apt/sources.list.d/syncthing.list
    apt-get update -qq
    apt-get install -y -qq syncthing
    echo "    installed $(syncthing --version | head -1)"
fi

echo "==> 2. Enable Syncthing user service for $OPERATOR"
# Syncthing runs as the operator, not root
sudo -u "$OPERATOR" bash -c '
    systemctl --user enable syncthing.service 2>/dev/null || true
    systemctl --user start syncthing.service 2>/dev/null || true
'
echo "    syncthing@$OPERATOR enabled"

echo "==> 3. Create vault directory"
install -d -m750 -o "$OPERATOR" -g "$OPERATOR" "$VAULT_DIR"
echo "    $VAULT_DIR (owner: $OPERATOR)"

echo "==> 4. Create client user: $CLIENT_USER"
if id "$CLIENT_USER" &>/dev/null; then
    echo "    user $CLIENT_USER already exists"
else
    useradd -r -m -s /bin/bash -G "" "$CLIENT_USER"
    # No sudo, no docker, no special groups — scoped access only
    echo "    created $CLIENT_USER (no sudo, no docker)"
fi

# Grant obsidian user read access to the vault via group
if ! getent group obsidian-vault &>/dev/null; then
    groupadd obsidian-vault
fi
usermod -aG obsidian-vault "$CLIENT_USER"
usermod -aG obsidian-vault "$OPERATOR"
chgrp obsidian-vault "$VAULT_DIR"
chmod 2750 "$VAULT_DIR"   # setgid: new files inherit group
echo "    group obsidian-vault: $OPERATOR + $CLIENT_USER can access vault"

echo "==> 5. Generate per-client Hermes key"
SSH_DIR="$HERMES_HOME/ssh"
KEY="$SSH_DIR/hermes_${CLIENT_USER}_id_ed25519"
if [ -f "$KEY" ]; then
    echo "    key exists: $KEY"
else
    sudo -u "$OPERATOR" ssh-keygen -t ed25519 -f "$KEY" -N "" \
        -C "hermes-${CLIENT_USER}@$(hostname)" -q
    chmod 600 "$KEY"
    chmod 644 "$KEY.pub"
    echo "    generated $KEY"
fi

echo "==> 6. Authorize Hermes key for $CLIENT_USER"
CLIENT_HOME="/home/$CLIENT_USER"
AKF="$CLIENT_HOME/.ssh/authorized_keys"
PUB="$(cat "$KEY.pub")"
install -d -m700 -o "$CLIENT_USER" -g "$CLIENT_USER" "$CLIENT_HOME/.ssh"
touch "$AKF"
grep -qxF "$PUB" "$AKF" 2>/dev/null || printf '%s\n' "$PUB" >> "$AKF"
chown "$CLIENT_USER:$CLIENT_USER" "$AKF"
chmod 600 "$AKF"
echo "    hermes key authorized"

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo ""
echo "  1. Syncthing Web UI: http://localhost:8384"
echo "     - Add the vault folder: $VAULT_DIR"
echo "     - Set folder type: 'Send & Receive'"
echo ""
echo "  2. On your Mac, install Syncthing (brew install syncthing)"
echo "     - Pair with the workstation (exchange device IDs)"
echo "     - Share the same folder (point it at your Obsidian vault)"
echo ""
echo "  3. Migrate from iCloud:"
echo "     rsync -av ~/Library/Mobile\\ Documents/iCloud~md~obsidian/Documents/<vault>/ max@workstation:$VAULT_DIR/"
echo ""
echo "  4. Add SSH inventory entry for Hermes (in ~/.hermes/ssh/config):"
echo "     Host obsidian"
echo "       Hostname localhost"
echo "       User $CLIENT_USER"
echo "       IdentityFile /opt/hermes-ssh/hermes_${CLIENT_USER}_id_ed25519"
echo ""
echo "  5. iPhone: install Möbius Sync (Syncthing client for iOS)"
echo "     - Pair with workstation, sync the vault folder"
echo "     - Point Obsidian mobile at the synced folder"

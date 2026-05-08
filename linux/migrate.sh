#!/bin/bash

# migrate.sh: Set up a new Linux server and optionally migrate data from an existing one
# Designed for USB pendrive — copy this + Debian 12 ISO to a FAT32 USB
#
# Usage:
#   bash migrate.sh                              # Fresh setup only
#   bash migrate.sh --from workstation        # Setup + migrate data from old server
#   bash migrate.sh --offline --pendrive /mnt/usb  # No network, use tarball from USB
#
# Prerequisites:
#   - Fresh Debian 12 minimal install (SSH server enabled, no desktop)
#   - Run as your admin user (with sudo access), NOT as root
#   - Network connectivity (unless --offline)

set -e

# --- Defaults ---
FROM_HOST=""
ADMIN_USER="max"
OFFLINE=false
SKIP_BOOTSTRAP=false
PENDRIVE=""
DOTFILES_DIR="$HOME/.dotfiles"

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --from)          FROM_HOST="$2"; shift 2 ;;
        --admin)         ADMIN_USER="$2"; shift 2 ;;
        --offline)       OFFLINE=true; shift ;;
        --skip-bootstrap) SKIP_BOOTSTRAP=true; shift ;;
        --pendrive)      PENDRIVE="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,14p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Pre-flight ---
echo "=== Linux Server Migration ==="
echo ""

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run as root. Run as your admin user with sudo access."
    exit 1
fi

if ! sudo -v; then
    echo "ERROR: sudo access required."
    exit 1
fi

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi
echo "Architecture: $ARCH"

if [ -f /etc/debian_version ]; then
    echo "Debian: $(cat /etc/debian_version)"
else
    echo "WARNING: Not Debian — script may need adjustments."
fi

# Auto-detect pendrive
if [ -z "$PENDRIVE" ]; then
    for d in /media/*/migrate.sh /mnt/*/migrate.sh /mnt/usb/migrate.sh; do
        [ -f "$d" ] && PENDRIVE="$(dirname "$d")" && break
    done
fi
[ -n "$PENDRIVE" ] && echo "Pendrive: $PENDRIVE"
echo ""

# --- Phase 1: Laptop config ---
echo "[1/6] Configuring laptop for server use..."

# Ignore lid close (headless server mode)
sudo mkdir -p /etc/systemd/logind.conf.d
cat <<'EOF' | sudo tee /etc/systemd/logind.conf.d/lid.conf >/dev/null
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
sudo systemctl restart systemd-logind 2>/dev/null || true

# Disable console blanking
if [ -f /etc/default/grub ]; then
    if ! grep -q 'consoleblank=0' /etc/default/grub; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=0"/' /etc/default/grub
        sudo update-grub 2>/dev/null || true
    fi
fi

echo "  REMINDER: Set BIOS (F2) → Power Management → AC Recovery → Last State"
echo ""

# --- Phase 2: Bootstrap ---
echo "[2/6] Running bootstrap..."

if [ "$SKIP_BOOTSTRAP" = true ]; then
    echo "  skipped (--skip-bootstrap)"
elif [ "$OFFLINE" = true ]; then
    if [ -z "$PENDRIVE" ]; then
        echo "ERROR: --offline requires --pendrive or auto-detected pendrive"
        exit 1
    fi
    TARBALL="$PENDRIVE/dotfiles.tar.gz"
    if [ ! -f "$TARBALL" ]; then
        echo "ERROR: $TARBALL not found on pendrive"
        exit 1
    fi
    echo "  extracting dotfiles from pendrive..."
    tar xzf "$TARBALL" -C "$HOME/"
    "$DOTFILES_DIR/install"
    bash "$DOTFILES_DIR/linux/bootstrap.sh"
else
    if [ -d "$DOTFILES_DIR" ]; then
        echo "  dotfiles exist, running bootstrap..."
        bash "$DOTFILES_DIR/linux/bootstrap.sh"
    else
        echo "  cloning and bootstrapping..."
        bash <(curl -sL https://raw.githubusercontent.com/maxflorentin/dotfiles-mbairm4/main/linux/bootstrap.sh)
    fi
fi
echo ""

# --- Phase 3: Tailscale ---
echo "[3/6] Installing Tailscale..."

if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "  installed"
else
    echo "  already installed"
fi

if ! tailscale status &>/dev/null; then
    echo ""
    echo "  >>> Run now: sudo tailscale up"
    echo "  >>> Login with your Tailscale account"
    echo "  >>> Then note the IP: tailscale ip -4"
    echo ""
    read -rp "  Press Enter after Tailscale is authenticated (or Ctrl+C to skip)..."
fi

NEW_TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
echo "  Tailscale IP: $NEW_TS_IP"
echo ""

# --- Phase 4: User migration ---
if [ -n "$FROM_HOST" ]; then
    echo "[4/6] Migrating users from $FROM_HOST..."

    # Verify SSH access
    if ! ssh -o ConnectTimeout=5 "$ADMIN_USER@$FROM_HOST" "echo ok" &>/dev/null; then
        echo "ERROR: Cannot SSH to $ADMIN_USER@$FROM_HOST"
        echo "  Ensure SSH key auth is set up and the old server is reachable."
        exit 1
    fi

    # Get user list with UIDs from old server
    USERS=$(ssh "$ADMIN_USER@$FROM_HOST" \
        "getent passwd | awk -F: '\$3>=1000 && \$1!=\"nobody\" && \$1!=\"encryption_user\" && \$7 !~ /(nologin|false)\$/ && \$6 ~ /^\\/home\\// {print \$1\":\"\$3}'")

    # Get ecryptfs users
    ECRYPTFS_USERS=$(ssh "$ADMIN_USER@$FROM_HOST" \
        "ls /home/.ecryptfs/ 2>/dev/null | tr '\n' ' '") || ECRYPTFS_USERS=""

    while IFS=: read -r username uid; do
        [ -z "$username" ] && continue

        echo "  --- $username (UID $uid) ---"

        # Create user with matching UID
        if ! id "$username" &>/dev/null; then
            sudo useradd -m -s /bin/zsh -u "$uid" "$username"
            sudo chmod 700 "/home/$username"
            echo "    created"
        else
            echo "    exists (UID $(id -u "$username"))"
        fi

        # Add to docker group
        sudo usermod -aG docker "$username" 2>/dev/null || true

        # Rsync home
        if echo "$ECRYPTFS_USERS" | grep -qw "$username"; then
            echo "    ecryptfs user — syncing encrypted backing store"
            sudo mkdir -p "/home/.ecryptfs/$username"
            sudo rsync -az --progress \
                "$ADMIN_USER@$FROM_HOST:/home/.ecryptfs/$username/" \
                "/home/.ecryptfs/$username/"
            sudo rsync -az --progress \
                --exclude='.ecryptfs' --exclude='.Private' \
                "$ADMIN_USER@$FROM_HOST:/home/$username/" \
                "/home/$username/"
        else
            echo "    syncing home..."
            sudo rsync -az --progress \
                --exclude='.cache' --exclude='node_modules' \
                "$ADMIN_USER@$FROM_HOST:/home/$username/" \
                "/home/$username/"
        fi

        # Fix ownership
        sudo chown -R "$username:$username" "/home/$username"
        echo "    done"
    done <<< "$USERS"

    # SSH authorized_keys
    echo "  --- SSH authorized_keys ---"
    sudo mkdir -p /etc/ssh/authorized_keys
    sudo rsync -az "$ADMIN_USER@$FROM_HOST:/etc/ssh/authorized_keys/" /etc/ssh/authorized_keys/ 2>/dev/null || echo "    (none found)"

    # Ensure sshd uses /etc/ssh/authorized_keys/%u
    if ! grep -q '/etc/ssh/authorized_keys/%u' /etc/ssh/sshd_config 2>/dev/null; then
        sudo sed -i 's|#\?AuthorizedKeysFile.*|AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys|' /etc/ssh/sshd_config
    fi

    # Copy sshd Match blocks (ecryptfs password auth)
    MATCH_BLOCKS=$(ssh "$ADMIN_USER@$FROM_HOST" "grep -A2 'Match User' /etc/ssh/sshd_config 2>/dev/null") || true
    if [ -n "$MATCH_BLOCKS" ]; then
        echo "  --- sshd Match blocks ---"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if ! grep -qF "$line" /etc/ssh/sshd_config 2>/dev/null; then
                echo "$line" | sudo tee -a /etc/ssh/sshd_config >/dev/null
            fi
        done <<< "$MATCH_BLOCKS"
    fi

    sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null || true

    # WireGuard client configs
    echo "  --- WireGuard configs ---"
    sudo rsync -az "$ADMIN_USER@$FROM_HOST:/etc/wireguard/*.conf" /etc/wireguard/ 2>/dev/null || echo "    (none found)"

    echo ""
else
    echo "[4/6] No --from specified, skipping user migration."
    echo ""
fi

# --- Phase 5: Post-install checks ---
echo "[5/6] Post-install checks..."

echo "  users: $(getent passwd | awk -F: '$3>=1000 && $1!="nobody" && $7 !~ /(nologin|false)$/ && $6 ~ /^\/home\// {printf "%s ", $1}')"
echo "  docker: $(docker --version 2>/dev/null || echo 'not found')"
echo "  node: $(node --version 2>/dev/null || echo 'not found')"
echo "  tailscale: $(tailscale ip -4 2>/dev/null || echo 'not connected')"
echo "  zsh: $(zsh --version 2>/dev/null || echo 'not found')"
echo ""

# --- Phase 6: Summary ---
echo "[6/6] Done!"
echo ""
echo "=== Migration Complete ==="
echo ""
echo "Tailscale IP: $NEW_TS_IP"
echo ""
echo "Next steps:"
echo "  1. BIOS (F2): Power Management → AC Recovery → Last State"
echo "  2. On your Mac — update SSH config:"
echo "     sed -i '' 's/<old-workstation-tailscale-ip>/$NEW_TS_IP/g' ~/.ssh/config.d/workstation"
echo "  3. Verify:"
echo "     ssh workstation          # key auth as admin"
if [ -n "$ECRYPTFS_USERS" ]; then
    echo "  4. Test ecryptfs users (password login to verify mount):"
    for u in $ECRYPTFS_USERS; do
        echo "     ssh $u@$(hostname)       # enter password → home mounts"
    done
fi
echo ""
echo "Run 'work status' from your Mac to verify everything."

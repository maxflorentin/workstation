#!/bin/bash

# bootstrap: Set up a headless Linux workstation (ARM64 or x86_64)
# Run ON the target machine after fresh OS install
# Usage: curl -sL <raw-url> | bash  OR  scp + run locally

set -e

echo "=== Linux Workstation Bootstrap ==="
echo ""

ARCH="$(uname -m)"
DEFAULT_DOTFILES_REPO="https://github.com/maxflorentin/workstation.git"
DOTFILES_DIR="$HOME/.dotfiles"
DOTFILES_REPO="${WORKSTATION_DOTFILES_REPO:-${WORK_DOTFILES_REPO:-$DEFAULT_DOTFILES_REPO}}"

# --- Locale ---
echo "[1/10] Configuring locale..."
sudo locale-gen en_US.UTF-8 2>/dev/null || true
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 2>/dev/null || true
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# --- System update ---
echo "[2/10] Updating system..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# --- Core packages ---
echo "[3/10] Installing core packages..."
sudo apt-get install -y -qq \
    git curl wget unzip \
    build-essential cmake \
    tmux btop \
    openssh-server \
    age \
    jq ripgrep fd-find bat fzf eza autojump \
    zsh zsh-syntax-highlighting \
    lsof ecryptfs-utils \
    fastfetch shellcheck lm-sensors

# --- Docker ---
echo "[4/10] Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
else
    echo "  already installed"
fi

# --- Node (standalone) ---
echo "[5/10] Installing Node..."
if ! command -v node &>/dev/null; then
    NODE_VERSION="v22.15.0"
    if [ "$ARCH" = "aarch64" ]; then
        NODE_ARCH="arm64"
    elif [ "$ARCH" = "x86_64" ]; then
        NODE_ARCH="x64"
    else
        echo "  unsupported architecture: $ARCH"; exit 1
    fi
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
        | sudo tar -xJ --strip-components=1 -C /usr/local/
else
    echo "  already installed ($(node --version))"
fi

# --- Claude Code ---
echo "[6/10] Installing Claude Code..."
if ! command -v claude &>/dev/null; then
    sudo npm install -g @anthropic-ai/claude-code
else
    echo "  already installed ($(claude --version 2>/dev/null | head -1))"
fi

# --- Python (uv) ---
echo "[7/10] Installing Python tools..."
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
else
    echo "  already installed"
fi

# --- Neovim ---
echo "[8/10] Installing Neovim..."
if ! command -v nvim &>/dev/null; then
    if [ "$ARCH" = "aarch64" ]; then
        NVIM_VERSION="v0.11.6"
        curl -LO "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-arm64.tar.gz"
        sudo tar xzf nvim-linux-arm64.tar.gz -C /opt/
        sudo ln -sf /opt/nvim-linux-arm64/bin/nvim /usr/local/bin/nvim
        rm nvim-linux-arm64.tar.gz
    else
        sudo apt-get install -y -qq neovim
    fi
else
    echo "  already installed"
fi

# --- Starship prompt ---
echo "[9/11] Installing Starship..."
if ! command -v starship &>/dev/null; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
else
    echo "  already installed"
fi

# --- Linuxbrew + workmux + yq ---
# Workmux drives the tmux-layout via a shared YAML config (yq parses it).
# Both are installed via Linuxbrew to keep the toolchain identical to the Mac.
echo "[10/11] Installing Linuxbrew + workmux + yq..."
if ! command -v brew &>/dev/null; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Make brew available for the rest of this script
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
    eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi

if command -v brew &>/dev/null; then
    brew tap jesseduffield/lazydocker 2>/dev/null || true
    brew tap raine/workmux 2>/dev/null || true
    brew install yq raine/workmux/workmux jesseduffield/lazydocker/lazydocker
else
    echo "  WARNING: brew install failed; workmux/yq missing — work CLI will refuse to run"
fi

# --- Dotfiles ---
echo "[11/11] Setting up dotfiles..."

if [ -d "$DOTFILES_DIR" ]; then
    echo "  pulling latest..."
    git -C "$DOTFILES_DIR" pull
else
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# Run the unified install script
"$DOTFILES_DIR/install"

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
fi

# --- ecryptfs SSH fix ---
# When home is encrypted, authorized_keys must live outside ~/
if dpkg -l ecryptfs-utils 2>/dev/null | grep -q '^ii'; then
    echo "Configuring SSH for ecryptfs compatibility..."
    sudo mkdir -p /etc/ssh/authorized_keys
    if [ -f "$HOME/.ssh/authorized_keys" ]; then
        sudo cp "$HOME/.ssh/authorized_keys" "/etc/ssh/authorized_keys/$USER"
        sudo chmod 644 "/etc/ssh/authorized_keys/$USER"
        sudo chown root:root "/etc/ssh/authorized_keys/$USER"
    fi
    if ! grep -q '/etc/ssh/authorized_keys/%u' /etc/ssh/sshd_config 2>/dev/null; then
        sudo sed -i 's|#\?AuthorizedKeysFile.*|AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys|' /etc/ssh/sshd_config
        sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null || true
    fi
fi

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (or: exec zsh)"
echo "  2. Authenticate Tailscale: sudo tailscale up"
echo "  3. Run validation: workstation doctor && work doctor && work vpn-doctor"
echo "  4. Create client users from the Mac: work user-create <client>"
echo "  5. For compliance-profile clients: sudo ~/.local/bin/work compliance-doctor <client>"
echo ""
echo "Dotfiles: ~/.dotfiles/"

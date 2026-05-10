# Add directories to the PATH and prevent to add the same directory multiple times upon shell reload.
add_to_path() {
  if [[ -d "$1" ]] && [[ ":$PATH:" != *":$1:"* ]]; then
    export PATH="$1:$PATH"
  fi
}

# Local bin (envy, scripts symlinks)
add_to_path "$HOME/.local/bin"

# Dotfiles scripts
add_to_path "$DOTFILES/scripts"

# Load global Node installed binaries
add_to_path "${NODE_BIN:-$HOME/.node/bin}"
add_to_path "node_modules/.bin"

# User-local npm global packages (for users without write access to /usr/local)
add_to_path "$HOME/.npm-global/bin"

# Antigravity
add_to_path "${ANTIGRAVITY_BIN:-$HOME/.antigravity/antigravity/bin}"

# fnm (Node version manager)
add_to_path "$HOME/.local/share/fnm"
if command -v fnm &>/dev/null && fnm --version &>/dev/null; then
  eval "$(fnm env)"
fi

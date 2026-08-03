# Shortcuts
alias copyssh="pbcopy < $HOME/.ssh/id_ed25519.pub"
alias reloadshell="exec zsh"
alias dotpull='git -C ~/.dotfiles pull --rebase --autostash origin main && ~/.dotfiles/install && exec zsh'
alias reloaddns="dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
alias l="eza -l --group-directories-first --icons"
alias ll="eza -la --group-directories-first --icons --git"
alias phpstorm='open -a "${PHPSTORM_APP:-/Applications/PhpStorm.app}" "`pwd`"'
alias shrug="echo '¯\_(ツ)_/¯' | pbcopy"
alias timestamp="date +%s"

# Remote tmux can leave the local terminal in mouse/reporting modes when SSH
# exits abruptly. Keep direct `ssh workstation` as safe as the `work` wrapper.
_ssh_restore_terminal() {
    local tty_state="${1:-}"

    if [[ -t 1 ]]; then
        printf '\033[?1l\033>\033[?1000l\033[?1002l\033[?1003l\033[?1004l\033[?1005l\033[?1006l\033[?1015l\033[?2004l\033[0m'
    fi

    if [[ -t 0 ]]; then
        if [[ -n "$tty_state" ]]; then
            stty "$tty_state" 2>/dev/null || stty sane 2>/dev/null || true
        else
            stty sane 2>/dev/null || true
        fi
    fi
}

ssh() {
    local tty_state ssh_status
    tty_state="$(stty -g 2>/dev/null || true)"
    ssh_status=0

    command ssh "$@" || ssh_status=$?
    _ssh_restore_terminal "$tty_state"
    return "$ssh_status"
}

# Directories
alias dotfiles="cd $DOTFILES"
alias library="cd $HOME/Library"

# Common
alias c="clear"
alias vim=nvim
alias k=kubectl

# Debian/Raspbian ships bat as batcat and fd as fdfind
if [[ "$(uname)" == "Linux" ]]; then
    command -v batcat &>/dev/null && alias bat='batcat'
    command -v fdfind &>/dev/null && alias fd='fdfind'
fi

# Docker/Podman (only alias if podman exists)
if command -v podman &>/dev/null; then
    alias docker=podman
    alias docker-compose='podman compose'
fi
alias dps='podman ps'
alias dimgs='podman images'
alias drun='podman run'
alias dbuild='podman build'
alias dstart='podman start'
alias dstop='podman stop'
alias drm='podman rm'
alias drmi='podman rmi'
alias dexec='podman exec'
alias dlogs='podman logs'
alias dnet='podman network'
alias dvol='podman volume'

# SQL Server
alias mssql='docker run -e ACCEPT_EULA=Y -e SA_PASSWORD="${MSSQL_PASSWORD:?Set MSSQL_PASSWORD env var}" -p 1433:1433 mcr.microsoft.com/mssql/server:2017-latest'

# Git
alias g="git"
alias gs="git status"
alias gb="git branch"
alias gc="git checkout"
alias gl="git log --oneline --decorate --color"
alias gd="git diff"
alias amend="git add . && git commit --amend --no-edit"
alias commit="git add . && git commit -m"
alias force="git push --force-with-lease"
alias nuke="git clean -df && git reset --hard"
alias pop="git stash pop"
alias prune="git fetch --prune"
alias pull="git pull"
alias push="git push"
alias resolve="git add . && git commit --no-edit"
alias stash="git stash -u"
alias unstage="git restore --staged ."
alias wip="commit wip"
alias compile="commit 'compile'"
alias version="commit 'version'"

# SQLit
alias sqlit-conn='sqlit-add-connection'

# Envy (encrypted secrets)
alias ev='envy-list'
alias evl='envy-load'
alias evs='envy-set'
alias evg='envy-get'
alias evn='envy-new'
alias evrm='envy-rm'
alias evsw='envy-switch'

# Claude / AI
# `clau` is now a PATH script (scripts/clau): resume-or-start. An alias here
# would shadow it in interactive shells.

# Tmux / Workmux
alias wm='workmux'

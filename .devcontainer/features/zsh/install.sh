#!/bin/bash

set -euo pipefail

# --- lib ---
error() { echo "[ERROR] $1" >&2; exit 1; }
info()  { echo "[INFO] $1" >&2; }

resolve_git_tag() {
  if [ "$1" = "latest" ]; then
    # Store full output first to avoid `| head -1` SIGPIPE under pipefail.
    local tags first
    tags=$(git -c 'versionsort.suffix=-' ls-remote --tags --sort=-v:refname \
      "https://github.com/$2.git" 'v*')
    first="${tags%%$'\n'*}"
    echo "${first##*/}"
  else
    echo "$1"
  fi
}

remote_home() {
  local home
  home="$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)"
  [ -n "$home" ] || error "Cannot resolve home for ${_REMOTE_USER}"
  echo "$home"
}

# --- main ---

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends zsh
apt-get distclean

# zsh-autosuggestions
if [ "${AUTOSUGGESTIONSVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_git_tag "${AUTOSUGGESTIONSVERSION:-latest}" zsh-users/zsh-autosuggestions)
  ZSH_AUTOSUGGESTIONS="/usr/local/share/zsh-autosuggestions"
  git clone --depth=1 --branch "$TAG" https://github.com/zsh-users/zsh-autosuggestions.git "${ZSH_AUTOSUGGESTIONS}"
  rm -rf "${ZSH_AUTOSUGGESTIONS}/.git"
  info "Installed zsh-autosuggestions ${TAG}"
fi

REMOTE_HOME="$(remote_home)"

cat > "${REMOTE_HOME}/.zshrc" << 'ZSHRC'
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:descriptions' format '%F{green}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'

HISTFILE=${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history
[ -d ${HISTFILE:h} ] || mkdir -p ${HISTFILE:h}
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '%F{green}+'
zstyle ':vcs_info:git:*' unstagedstr '%F{yellow}*'
zstyle ':vcs_info:git:*' formats '%F{green}git:(%F{yellow}%b%c%u%F{green})%f'
zstyle ':vcs_info:git:*' actionformats '%F{green}git:(%F{yellow}%b|%a%c%u%F{green})%f'
precmd() { vcs_info }
setopt PROMPT_SUBST
PROMPT='%F{magenta}%n@%m %F{cyan}[%D{%y-%m-%d %H:%M:%S}] %F{yellow}%~ ${vcs_info_msg_0_}%f
$ '

[ -f /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
  source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh

command -v fzf    > /dev/null && source <(fzf --zsh)
command -v fd     > /dev/null && export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
command -v bat    > /dev/null && export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border --preview "bat --color=always --style=numbers --line-range=:500 {}" --bind ctrl-/:toggle-preview'
command -v zoxide > /dev/null && eval "$(zoxide init zsh)"
# fnm env already eval'd in /etc/profile.d/node.sh via zprofile emulation;
# no need to re-eval here.
ZSHRC

chown "${_REMOTE_USER}:" "${REMOTE_HOME}/.zshrc"
info "Created ${REMOTE_HOME}/.zshrc"

chsh --shell /bin/zsh "${_REMOTE_USER}"

# /etc/zsh/zprofile — source /etc/profile.d/*.sh via POSIX emulation
cat > /etc/zsh/zprofile << 'EOF'
emulate sh -c 'source /etc/profile'
EOF

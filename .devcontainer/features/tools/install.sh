#!/bin/bash

set -euo pipefail

# --- lib ---
error() { echo "[ERROR] $1" >&2; exit 1; }
info()  { echo "[INFO] $1" >&2; }

case "$(uname -m)" in
  x86_64)  ARCH="x86_64"; GOARCH="amd64" ;;
  aarch64) ARCH="aarch64"; GOARCH="arm64" ;;
  *)       error "Unsupported architecture: $(uname -m)" ;;
esac

readonly GNU="${ARCH}-unknown-linux-gnu"
readonly MUSL="${ARCH}-unknown-linux-musl"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

resolve_release_tag() {
  if [ "$1" = "latest" ]; then
    curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/$2/releases/latest" \
      | sed 's|.*/||'
  else
    echo "$1"
  fi
}

verify_checksum() {
  local file=$1 expected=$2
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    error "Checksum mismatch for $(basename "$file"): expected $expected, got $actual"
  fi
}

fetch_checksum() {
  local url=$1 filename=$2
  local line
  line=$(curl -fsSL "$url" 2>/dev/null | grep -F "$filename" | head -1) || true
  echo "${line%% *}"
}

# tar xf auto-detects gzip / xz / bzip2, so one helper handles both .tar.gz and
# .tar.xz (xz-utils is in the apt feature base packages).
install_tar() {
  local name=$1 url=$2 bin=${3:-$1} checksum=${4:-}
  local archive="${TEMP_DIR}/archive"
  curl -fsSL "$url" -o "$archive"
  if [ -n "$checksum" ]; then verify_checksum "$archive" "$checksum"; fi
  tar xf "$archive" -C "${TEMP_DIR}"
  find "${TEMP_DIR}" -name "$bin" -type f -exec install -m 0755 {} /usr/local/bin/ \;
  rm -rf "${TEMP_DIR:?}"/*
  info "Installed $name"
}

install_zip() {
  local name=$1 url=$2 bin=${3:-$1} checksum=${4:-}
  local archive="${TEMP_DIR}/archive.zip"
  curl -fsSL "$url" -o "$archive"
  if [ -n "$checksum" ]; then verify_checksum "$archive" "$checksum"; fi
  unzip -qo "$archive" -d "${TEMP_DIR}"
  find "${TEMP_DIR}" -name "$bin" -type f -exec install -m 0755 {} /usr/local/bin/ \;
  rm -rf "${TEMP_DIR:?}"/*
  info "Installed $name"
}

# For projects that ship a bare executable (no archive), e.g. shfmt.
install_bin() {
  local name=$1 url=$2 checksum=${3:-}
  curl -fsSL "$url" -o "${TEMP_DIR}/${name}"
  if [ -n "$checksum" ]; then verify_checksum "${TEMP_DIR}/${name}" "$checksum"; fi
  install -m 0755 "${TEMP_DIR}/${name}" "/usr/local/bin/${name}"
  rm -rf "${TEMP_DIR:?}"/*
  info "Installed $name"
}

install_app() {
  local name=$1 url=$2 dest=$3 bin=$4 checksum=${5:-}
  local archive="${TEMP_DIR}/archive"
  curl -fsSL "$url" -o "$archive"
  if [ -n "$checksum" ]; then verify_checksum "$archive" "$checksum"; fi
  tar xf "$archive" -C "$dest"
  local bin_path
  bin_path=$(find "$dest" -name "$bin" -type f | head -1)
  [ -n "$bin_path" ] || error "Binary $bin not found in $dest"
  ln -sf "$bin_path" "/usr/local/bin/$bin"
  rm -rf "${TEMP_DIR:?}"/*
  info "Installed $name"
}

# --- main ---

readonly GH="https://github.com"

if [ "${BATVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$BATVERSION" sharkdp/bat)
  install_tar bat "$GH/sharkdp/bat/releases/download/$TAG/bat-${TAG}-${MUSL}.tar.gz"
fi

# delta: gnu-only on aarch64
if [ "${DELTAVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$DELTAVERSION" dandavison/delta)
  install_tar delta "$GH/dandavison/delta/releases/download/$TAG/delta-${TAG}-${GNU}.tar.gz"
fi

# eza: no version in filename
if [ "${EZAVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$EZAVERSION" eza-community/eza)
  install_tar eza "$GH/eza-community/eza/releases/download/$TAG/eza_${GNU}.tar.gz"
fi

if [ "${FDVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$FDVERSION" sharkdp/fd)
  install_tar fd "$GH/sharkdp/fd/releases/download/$TAG/fd-${TAG}-${MUSL}.tar.gz"
fi

# fzf: v stripped, GOARCH
if [ "${FZFVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$FZFVERSION" junegunn/fzf)
  FZF_ARCHIVE="fzf-${TAG#v}-linux_${GOARCH}.tar.gz"
  CHECKSUM=$(fetch_checksum "$GH/junegunn/fzf/releases/download/$TAG/fzf_${TAG#v}_checksums.txt" "$FZF_ARCHIVE")
  install_tar fzf "$GH/junegunn/fzf/releases/download/$TAG/$FZF_ARCHIVE" fzf "$CHECKSUM"
fi

# gh: v stripped, GOARCH
if [ "${GHVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$GHVERSION" cli/cli)
  GH_ARCHIVE="gh_${TAG#v}_linux_${GOARCH}.tar.gz"
  CHECKSUM=$(fetch_checksum "$GH/cli/cli/releases/download/$TAG/gh_${TAG#v}_checksums.txt" "$GH_ARCHIVE")
  install_tar gh "$GH/cli/cli/releases/download/$TAG/$GH_ARCHIVE" gh "$CHECKSUM"
fi

if [ "${HYPERFINEVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$HYPERFINEVERSION" sharkdp/hyperfine)
  install_tar hyperfine "$GH/sharkdp/hyperfine/releases/download/$TAG/hyperfine-${TAG}-${GNU}.tar.gz"
fi

# just: v stripped, musl-only
if [ "${JUSTVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$JUSTVERSION" casey/just)
  install_tar just "$GH/casey/just/releases/download/$TAG/just-${TAG#v}-${MUSL}.tar.gz"
fi

# lazygit: v stripped
if [ "${LAZYGITVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$LAZYGITVERSION" jesseduffield/lazygit)
  LG_ARCHIVE="lazygit_${TAG#v}_linux_${ARCH/aarch64/arm64}.tar.gz"
  CHECKSUM=$(fetch_checksum "$GH/jesseduffield/lazygit/releases/download/$TAG/checksums.txt" "$LG_ARCHIVE")
  install_tar lazygit "$GH/jesseduffield/lazygit/releases/download/$TAG/$LG_ARCHIVE" lazygit "$CHECKSUM"
fi

# neovim: /opt install, symlinked launcher
if [ "${NEOVIMVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$NEOVIMVERSION" neovim/neovim)
  install_app neovim "$GH/neovim/neovim/releases/download/$TAG/nvim-linux-${ARCH/aarch64/arm64}.tar.gz" /opt nvim
fi

# ripgrep: musl on x86_64, gnu on aarch64
if [ "${RIPGREPVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$RIPGREPVERSION" BurntSushi/ripgrep)
  if [ "${ARCH}" = "aarch64" ]; then RG_TARGET="${GNU}"; else RG_TARGET="${MUSL}"; fi
  RG_ARCHIVE="ripgrep-${TAG}-${RG_TARGET}.tar.gz"
  CHECKSUM=$(fetch_checksum "$GH/BurntSushi/ripgrep/releases/download/$TAG/${RG_ARCHIVE}.sha256" "$RG_ARCHIVE")
  install_tar ripgrep "$GH/BurntSushi/ripgrep/releases/download/$TAG/$RG_ARCHIVE" rg "$CHECKSUM"
fi

# shellcheck: .tar.xz (tar xf auto-detects xz via xz-utils from apt feature)
if [ "${SHELLCHECKVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$SHELLCHECKVERSION" koalaman/shellcheck)
  install_tar shellcheck "$GH/koalaman/shellcheck/releases/download/$TAG/shellcheck-${TAG}.linux.${ARCH}.tar.xz"
fi

# shfmt: bare binary
if [ "${SHFMTVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$SHFMTVERSION" mvdan/sh)
  install_bin shfmt "$GH/mvdan/sh/releases/download/$TAG/shfmt_${TAG}_linux_${GOARCH}"
fi

# yazi: no version in filename
if [ "${YAZIVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$YAZIVERSION" sxyazi/yazi)
  install_zip yazi "$GH/sxyazi/yazi/releases/download/$TAG/yazi-${MUSL}.zip"
fi

# zoxide: v stripped
if [ "${ZOXIDEVERSION:-latest}" != "none" ]; then
  TAG=$(resolve_release_tag "$ZOXIDEVERSION" ajeetdsouza/zoxide)
  install_tar zoxide "$GH/ajeetdsouza/zoxide/releases/download/$TAG/zoxide-${TAG#v}-${MUSL}.tar.gz"
fi

# System-wide git config (delta pager + sensible defaults). Per-user config
# still loads via ~/.gitconfig or $GIT_CONFIG_GLOBAL / $XDG_CONFIG_HOME/git/config.
cat > /etc/gitconfig << 'GITCONFIG'
[core]
	pager = delta
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
	line-numbers = true
[merge]
	conflictstyle = zdiff3
[init]
	defaultBranch = main
[pull]
	ff = only
[safe]
	directory = *
GITCONFIG
info "Wrote /etc/gitconfig"

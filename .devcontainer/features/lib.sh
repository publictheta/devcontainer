#!/bin/bash
# Shared helpers reference — each install.sh inlines only what it needs.
# This file is NOT sourced at runtime; it documents the canonical patterns.

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

# Via GitHub Releases redirect (most repos).
resolve_release_tag() {
  if [ "$1" = "latest" ]; then
    curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/$2/releases/latest" \
      | sed 's|.*/||'
  else
    echo "$1"
  fi
}

# Via git ls-remote (repos without GitHub Releases).
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

verify_checksum() {
  local file=$1 expected=$2
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    error "Checksum mismatch for $(basename "$file"): expected $expected, got $actual"
  fi
}

# Returns empty on failure; caller skips verification.
fetch_checksum() {
  local url=$1 filename=$2
  local line
  line=$(curl -fsSL "$url" 2>/dev/null | grep -F "$filename" | head -1) || true
  echo "${line%% *}"
}

# tar xf auto-detects gzip / xz / bzip2 — handles .tar.gz and .tar.xz both
# (xz-utils must be in apt base packages).
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

# For apps that install to /opt and symlink a launcher (e.g. neovim).
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

# Group + setgid for shared dirs; survives updateRemoteUserUID.
setup_shared_group() {
  local group=$1; shift
  groupadd -r "$group"
  usermod -a -G "$group" "${_REMOTE_USER}"
  chown -R "root:$group" "$@"
  # Single tree walk: g+rw on everything, g+s added only on dirs.
  find "$@" \( -type d -exec chmod g+rws {} + \) -o \( -exec chmod g+rw {} + \)
}

# $_REMOTE_USER_HOME may be empty; resolve from /etc/passwd instead.
remote_home() {
  local home
  home="$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)"
  [ -n "$home" ] || error "Cannot resolve home for ${_REMOTE_USER}"
  echo "$home"
}

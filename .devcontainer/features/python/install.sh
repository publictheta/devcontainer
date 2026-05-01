#!/bin/bash

set -euo pipefail

# --- lib ---
error() { echo "[ERROR] $1" >&2; exit 1; }
info()  { echo "[INFO] $1" >&2; }

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|aarch64) ;;
  *) error "Unsupported architecture: ${ARCH}" ;;
esac
readonly ARCH
readonly GNU="${ARCH}-unknown-linux-gnu"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

setup_shared_group() {
  local group=$1; shift
  groupadd -r "$group"
  usermod -a -G "$group" "${_REMOTE_USER}"
  chown -R "root:$group" "$@"
  # Single tree walk: g+rw on everything, g+s added only on dirs.
  find "$@" \( -type d -exec chmod g+rws {} + \) -o \( -exec chmod g+rw {} + \)
}

resolve_release_tag() {
  if [ "$1" = "latest" ]; then
    curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/$2/releases/latest" \
      | sed 's|.*/||'
  else
    echo "$1"
  fi
}

install_tar() {
  local name=$1 url=$2 bin=${3:-$1}
  local archive="${TEMP_DIR}/archive.tar.gz"
  curl -fsSL "$url" -o "$archive"
  tar xf "$archive" -C "${TEMP_DIR}"
  find "${TEMP_DIR}" -name "$bin" -type f -exec install -m 0755 {} /usr/local/bin/ \;
  rm -rf "${TEMP_DIR:?}"/*
  info "Installed $name"
}

# --- main ---

readonly VERSION="${VERSION:-latest}"
readonly RUFFVERSION="${RUFFVERSION:-latest}"
readonly TYVERSION="${TYVERSION:-latest}"
readonly UV_DIR="/usr/local/share/uv"
readonly UV_PYTHON_INSTALL_DIR="${UV_DIR}/python"

# uv (upstream native binary from astral-sh/uv). The tarball ships two
# binaries (uv + uvx) so we inline rather than reuse install_tar (single-bin).
curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-${GNU}.tar.gz" \
  | tar xz -C "${TEMP_DIR}" --strip-components=1
install -m 0755 "${TEMP_DIR}/uv" "${TEMP_DIR}/uvx" /usr/local/bin/
rm -rf "${TEMP_DIR:?}"/*
info "Installed uv"

# Python interpreter via uv — lands in /usr/local/share/uv/python.
# Load-bearing for VERSION=none: the mkdir below ensures setup_shared_group has
# a directory to chown, so `uv python install` can be used at runtime later.
if [ "${VERSION}" != "none" ]; then
  export UV_PYTHON_INSTALL_DIR
  export XDG_BIN_HOME="/usr/local/bin"

  if [ "${VERSION}" = "latest" ]; then
    uv python install --default
  else
    uv python install --default "${VERSION}"
  fi
  info "Installed Python ${VERSION}"
fi

# Pre-create shared uv paths so that user-declared volume mounts at these
# locations inherit correct ownership on first mount (minikube pattern: Docker
# preserves the metadata of the existing image dir). Also load-bearing for
# VERSION=none where uv python install never ran.
mkdir -p "${UV_PYTHON_INSTALL_DIR}" "${UV_DIR}/tools"

# ruff (Astral, Rust-native linter/formatter) — binary directly in /usr/local/bin
# so user's `uv tool install ruff@<ver>` at ~/.local/bin can shadow it via PATH.
if [ "${RUFFVERSION}" != "none" ]; then
  TAG=$(resolve_release_tag "${RUFFVERSION}" astral-sh/ruff)
  install_tar ruff "https://github.com/astral-sh/ruff/releases/download/${TAG}/ruff-${GNU}.tar.gz"
fi

# ty — same PATH-shadow pattern as ruff above
if [ "${TYVERSION}" != "none" ]; then
  TAG=$(resolve_release_tag "${TYVERSION}" astral-sh/ty)
  install_tar ty "https://github.com/astral-sh/ty/releases/download/${TAG}/ty-${GNU}.tar.gz"
fi

setup_shared_group uv "${UV_DIR}"

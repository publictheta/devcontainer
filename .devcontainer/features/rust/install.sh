#!/bin/bash

set -euo pipefail

# --- lib ---
error() { echo "[ERROR] $1" >&2; exit 1; }
info()  { echo "[INFO] $1" >&2; }

case "$(uname -m)" in
  x86_64|aarch64) ;;
  *) error "Unsupported architecture: $(uname -m)" ;;
esac

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

# --- main ---

readonly VERSION="${VERSION:-stable}"
readonly PROFILE="${PROFILE:-minimal}"
readonly COMPONENTS="${COMPONENTS:-rust-analyzer,rust-src,rustfmt,clippy}"
readonly TARGETS="${TARGETS:-}"
readonly TARGET="$(uname -m)-unknown-linux-gnu"
readonly RUSTUP_HOME="/usr/local/rustup"
readonly CARGO_HOME="/usr/local/cargo"

export RUSTUP_HOME CARGO_HOME

# rustup accepts literal `none` as --default-toolchain; pass VERSION directly.
curl -fsSL "https://static.rust-lang.org/rustup/dist/${TARGET}/rustup-init" \
  -o "${TEMP_DIR}/rustup-init"
chmod +x "${TEMP_DIR}/rustup-init"
"${TEMP_DIR}/rustup-init" -y --no-modify-path \
  --default-host "${TARGET}" \
  --profile "${PROFILE}" \
  --default-toolchain "${VERSION}"

RUSTUP="${CARGO_HOME}/bin/rustup"

if [ "${VERSION}" != "none" ]; then
  # Multi-arg calls avoid one manifest fetch per item.
  if [ "${COMPONENTS}" != "none" ] && [ -n "${COMPONENTS}" ]; then
    # shellcheck disable=SC2086 # intentional word splitting on commas
    "${RUSTUP}" component add ${COMPONENTS//,/ }
    info "Added components: ${COMPONENTS}"
  fi

  if [ "${TARGETS}" != "none" ] && [ -n "${TARGETS}" ]; then
    # shellcheck disable=SC2086
    "${RUSTUP}" target add ${TARGETS//,/ }
    info "Added targets: ${TARGETS}"
  fi

  info "Installed Rust ${VERSION} (${PROFILE} profile)"
else
  info "Installed rustup (no toolchain)"
fi

# Pre-create the empty-at-build cache subdirs so that a user-declared volume
# mount at these paths inherits the correct ownership on first mount
# (Docker's first-mount preserves metadata of the existing image dir). Without
# this, mounting a fresh named volume lands as root:root, unwritable by dev.
# Same pattern as the official `kubectl-helm-minikube` feature's mkdir+chown.
mkdir -p "${CARGO_HOME}/registry" "${CARGO_HOME}/git"

setup_shared_group rustlang "${RUSTUP_HOME}" "${CARGO_HOME}"

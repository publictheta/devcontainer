#!/bin/bash

set -euo pipefail

# --- lib ---
error() { echo "[ERROR] $1" >&2; exit 1; }
info()  { echo "[INFO] $1" >&2; }

case "$(uname -m)" in
  x86_64)  PLATFORM="linux-x64" ;;
  aarch64) PLATFORM="linux-arm64" ;;
  *)       error "Unsupported architecture: $(uname -m)" ;;
esac

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

verify_checksum() {
  local file=$1 expected=$2
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    error "Checksum mismatch for $(basename "$file"): expected $expected, got $actual"
  fi
}

# $_REMOTE_USER_HOME may be empty; resolve from /etc/passwd instead.
remote_home() {
  local home
  home="$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)"
  [ -n "$home" ] || error "Cannot resolve home for ${_REMOTE_USER}"
  echo "$home"
}

# --- main ---

readonly VERSION="${VERSION:-latest}"

if [ "${VERSION}" = "none" ]; then
  info "Skipping Claude Code install"
  exit 0
fi

readonly INSTALL_SCRIPT_URL="https://claude.ai/install.sh"

# `readonly X=$(curl)` masks curl failures from `set -e`, so split. Avoid
# `| head -1`: under pipefail it risks SIGPIPE on upstream when head closes
# the pipe early. sed reads all input and emits the match(es); the install
# script has exactly one DOWNLOAD_BASE_URL line so the result is single-line.
DOWNLOAD_BASE_URL=$(curl -fsSL "${INSTALL_SCRIPT_URL}" | sed -n 's/^DOWNLOAD_BASE_URL="\([^"]*\)".*/\1/p')
readonly DOWNLOAD_BASE_URL
[[ "${DOWNLOAD_BASE_URL}" =~ ^https:// ]] || error "Failed to extract DOWNLOAD_BASE_URL from install script"

RESOLVED_VERSION=$(curl -fsSL "${DOWNLOAD_BASE_URL}/${VERSION}")
readonly RESOLVED_VERSION
[ -n "${RESOLVED_VERSION}" ] || error "Failed to resolve Claude Code version"
info "Resolved version: ${RESOLVED_VERSION}"

MANIFEST=$(curl -fsSL "${DOWNLOAD_BASE_URL}/${RESOLVED_VERSION}/manifest.json")
[ -n "${MANIFEST}" ] || error "Failed to fetch manifest"
CHECKSUM=$(jq -r ".platforms[\"${PLATFORM}\"].checksum" <<< "${MANIFEST}")
if [ -z "${CHECKSUM}" ] || [ "${CHECKSUM}" = "null" ]; then
  error "Platform ${PLATFORM} not found in manifest"
fi

REMOTE_HOME="$(remote_home)"
BIN_DIR="${REMOTE_HOME}/.local/bin"
BIN_PATH="${BIN_DIR}/claude"

curl -fsSL "${DOWNLOAD_BASE_URL}/${RESOLVED_VERSION}/${PLATFORM}/claude" -o "${TEMP_DIR}/claude"
verify_checksum "${TEMP_DIR}/claude" "${CHECKSUM}"
install -d -o "${_REMOTE_USER}" -g "${_REMOTE_USER}" "${BIN_DIR}"
install -m 0755 -o "${_REMOTE_USER}" -g "${_REMOTE_USER}" "${TEMP_DIR}/claude" "${BIN_PATH}"

info "Installed Claude Code ${RESOLVED_VERSION} to ${BIN_PATH}"

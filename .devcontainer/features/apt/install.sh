#!/bin/bash

set -euo pipefail

# --- lib ---
info() { echo "[INFO] $1" >&2; }

# --- main ---

export DEBIAN_FRONTEND=noninteractive

BASE_PACKAGES=(
  build-essential
  ca-certificates
  curl
  git
  gnupg
  jq
  less
  locales
  openssh-client
  pkg-config
  procps
  sudo
  tzdata
  unzip
  wget
  xz-utils
)

apt-get update -y
# shellcheck disable=SC2086 # intentional word splitting on space-separated package names
apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}" ${PACKAGES:-}
apt-get distclean

info "Installed base packages"

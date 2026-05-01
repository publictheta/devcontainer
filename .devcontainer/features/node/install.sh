#!/bin/bash

set -euo pipefail

# --- lib ---
error() { echo "[ERROR] $1" >&2; exit 1; }
info()  { echo "[INFO] $1" >&2; }

case "$(uname -m)" in
  x86_64)  FNM_ARCHIVE="fnm-linux.zip" ;;
  aarch64) FNM_ARCHIVE="fnm-arm64.zip" ;;
  *)       error "Unsupported architecture: $(uname -m)" ;;
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

readonly VERSION="${VERSION:-latest}"
# Not readonly: `eval "$(fnm env)"` re-exports FNM_DIR.
FNM_DIR="/usr/local/share/fnm"

curl -fsSL "https://github.com/Schniz/fnm/releases/latest/download/${FNM_ARCHIVE}" \
  -o "${TEMP_DIR}/fnm.zip"
unzip -q "${TEMP_DIR}/fnm.zip" -d "${TEMP_DIR}"
install -m 0755 "${TEMP_DIR}/fnm" /usr/local/bin/fnm
info "Installed fnm"

# Pre-create FNM_DIR so fnm install can use it. node-versions subdir is created
# by fnm on first install; it's image-populated (latest version) so its
# first-mount copy propagates ownership — no explicit pre-create needed there.
mkdir -p "${FNM_DIR}"

if [ "${VERSION}" != "none" ]; then
  export FNM_DIR

  # umask 002: new files get g+w so subsequent runtime `fnm install <other>` by
  # the dev user (group fnm) lands with group-write perms, letting `corepack
  # enable` create pnpm/yarn shims inside the new version's bin dir.
  umask 002

  case "${VERSION}" in
    latest) fnm install --latest ;;
    lts)    fnm install --lts ;;
    *)      fnm install "${VERSION}" ;;
  esac

  eval "$(fnm env --shell bash)"

  # corepack was removed from Node.js 25+; install via npm if missing
  if ! command -v corepack > /dev/null 2>&1; then
    npm install -g corepack
  fi
  corepack enable

  # fnm install --latest automatically sets `${FNM_DIR}/aliases/default` to
  # the installed version. Our containerEnv.PATH statically references
  # `${FNM_DIR}/aliases/default/bin`, so non-login shells resolve node/npm/npx
  # /corepack/pnpm through that alias symlink. When a user later runs
  # `fnm default <version>` the symlink updates and PATH follows automatically.
  # This is the fnm equivalent of NVM_SYMLINK_CURRENT.

  info "Installed Node.js ${VERSION} (corepack enabled)"
fi

# Non-login-shell env uses containerEnv (FNM_DIR). Interactive shells also
# source this for fnm's shim PATH, which is node-version-aware and can't be
# expressed statically in containerEnv.
cat > /etc/profile.d/node.sh << 'EOF'
export FNM_DIR="${FNM_DIR:-/usr/local/share/fnm}"
command -v fnm > /dev/null && eval "$(fnm env --use-on-cd)"
EOF
info "Added /etc/profile.d/node.sh"

setup_shared_group fnm "${FNM_DIR}"

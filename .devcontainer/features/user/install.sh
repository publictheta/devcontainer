#!/bin/bash

set -euo pipefail

# --- lib ---
info() { echo "[INFO] $1" >&2; }

# --- main ---

# Name is hardcoded because downstream features and containerEnv values
# (/home/dev/...) cannot interpolate it — the option would have been a lie.
readonly USER_NAME="dev"
readonly USER_UID="${USERUID:-1000}"
readonly USER_GID="${USERGID:-1000}"

if ! getent group "${USER_NAME}" > /dev/null 2>&1; then
  groupadd -g "${USER_GID}" "${USER_NAME}"
fi
if ! id -u "${USER_NAME}" > /dev/null 2>&1; then
  useradd -m -u "${USER_UID}" -g "${USER_GID}" "${USER_NAME}"
fi

# Sudo
mkdir -p /etc/sudoers.d
echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USER_NAME}"
chmod 0440 "/etc/sudoers.d/${USER_NAME}"

# Locales
readonly LOCALES="${LOCALES:-en_US.UTF-8 ja_JP.UTF-8}"
LANG=""
# shellcheck disable=SC2086 # intentional word splitting on space-separated locales
for loc in ${LOCALES}; do
  echo "${loc} ${loc##*.}" >> /etc/locale.gen
  [ -z "${LANG}" ] && LANG="${loc}"
done
locale-gen
echo "LANG=${LANG}" > /etc/default/locale
info "Generated locales: ${LOCALES}"

# XDG base directories + .ssh. Pre-created with correct ownership so that any
# user-declared volume mount or host bind-mount on these paths inherits dev
# ownership on first mount (Docker's first-mount copy preserves target perms
# when the volume is empty).
install -d -o "${USER_UID}" -g "${USER_GID}" \
  "/home/${USER_NAME}/.cache" \
  "/home/${USER_NAME}/.config" \
  "/home/${USER_NAME}/.local" \
  "/home/${USER_NAME}/.local/bin" \
  "/home/${USER_NAME}/.local/share" \
  "/home/${USER_NAME}/.local/state" \
  "/home/${USER_NAME}/.ssh"
chmod 0700 "/home/${USER_NAME}/.ssh"

install -m 0755 "$(dirname "$0")/entrypoint.sh" \
  /usr/local/share/devcontainer-user-entrypoint.sh

cat > /etc/profile.d/user.sh << 'PROFILE'
export PATH="$HOME/.local/bin:$PATH"
PROFILE

info "Created user '${USER_NAME}' (${USER_UID}:${USER_GID})"

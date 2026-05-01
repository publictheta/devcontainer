#!/bin/sh
# Fix first-mount ownership of per-project named volumes that Docker creates
# as root:root because the workspace path is only known at container start.
# Targets empty, root-owned directories exactly two levels under /workspaces;
# no-op on subsequent starts once ownership is fixed.
set -e

find /workspaces -mindepth 2 -maxdepth 2 -type d -uid 0 -empty \
	-exec chown dev:dev {} + 2>/dev/null || true

exec "$@"

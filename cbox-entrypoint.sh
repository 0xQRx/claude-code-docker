#!/bin/bash
# Root entrypoint used by the `cbox` CLI launcher.
# 1. Remaps the in-container `claude` user to the host UID/GID so files written
#    into /workspace are owned by the host user (not root).
# 2. Optionally applies the egress firewall (CBOX_LOCKED=1).
# 3. Drops privileges to `claude` and execs the requested command.
set -euo pipefail

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"

# Remap claude's gid/uid if the host differs from the image default (1000).
if [ "$HOST_GID" != "$(id -g claude)" ]; then
  groupmod -o -g "$HOST_GID" claude
fi
if [ "$HOST_UID" != "$(id -u claude)" ]; then
  usermod -o -u "$HOST_UID" claude
fi

# Make sure home + persisted volumes are owned by the (possibly remapped) claude.
# .cache, .claude and /commandhistory are separately-mounted volumes, so chowning
# /home/claude (non-recursive) does not cover them — chown each mountpoint, and do
# it recursively for the ones that hold image-baked files (commandhistory's
# .bash_history, .claude config) whose build-time owner (uid 1000) won't match a
# non-root host user, otherwise writes fail (history error / re-fetched caches).
chown "$HOST_UID:$HOST_GID" /home/claude /home/claude/.cache 2>/dev/null || true
chown -R "$HOST_UID:$HOST_GID" /commandhistory /home/claude/.claude 2>/dev/null || true

# Optional egress allowlist firewall (needs --cap-add=NET_ADMIN,NET_RAW).
if [ "${CBOX_LOCKED:-0}" = "1" ]; then
  /usr/local/bin/init-firewall.sh
fi

export HOME=/home/claude
cd /workspace

# Default to launching Claude if no explicit command was given.
if [ "$#" -eq 0 ]; then
  set -- claude
fi

exec gosu claude:claude "$@"

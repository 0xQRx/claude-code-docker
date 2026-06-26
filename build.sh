#!/usr/bin/env bash
# build.sh — one-shot installer for claude-box.
#
#   1. Builds the Docker image (claude-box:latest).
#   2. Symlinks `cbox` into ~/.local/bin so it's available from anywhere
#      (and ensures ~/.local/bin is on PATH). Idempotent — safe to re-run.
#
# Usage:
#   ./build.sh                # build + install the cbox symlink
#   ./build.sh --no-path      # build only, skip the symlink/PATH changes
#   ./build.sh --no-build     # symlink/PATH changes only, skip the build
#   ./build.sh -- <args...>   # forward extra args to `docker build`
#
set -euo pipefail

IMAGE="claude-box:latest"
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BIN_DIR="$HOME/.local/bin"
MARKER="# >>> cbox >>>"
END_MARKER="# <<< cbox <<<"

DO_BUILD=1
DO_PATH=1
BUILD_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --no-path)  DO_PATH=0; shift ;;
    --)         shift; BUILD_ARGS+=("$@"); break ;;
    *)          BUILD_ARGS+=("$1"); shift ;;
  esac
done

# --- 1. Build -------------------------------------------------------------
if [ "$DO_BUILD" = 1 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed or not on PATH." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: the Docker daemon is not running or not reachable." >&2
    exit 1
  fi
  echo "Building $IMAGE ..."
  docker build -t "$IMAGE" ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} "$DIR"
  echo "Built $IMAGE."
fi

# --- 2. Symlink cbox + ensure ~/.local/bin is on PATH (idempotent) -------
chmod +x "$DIR/cbox" "$DIR/cbox-entrypoint.sh" 2>/dev/null || true

# Append the ~/.local/bin PATH line to an rc file, only if not already present.
ensure_bin_on_path() {
  local rc="$1"
  touch "$rc"
  if grep -qF "$MARKER" "$rc"; then
    return
  fi
  {
    echo "$MARKER"
    echo "case \":\$PATH:\" in *\":$BIN_DIR:\"*) ;; *) export PATH=\"$BIN_DIR:\$PATH\" ;; esac"
    echo "$END_MARKER"
  } >> "$rc"
  echo "Added $BIN_DIR to PATH in $rc"
}

if [ "$DO_PATH" = 1 ]; then
  mkdir -p "$BIN_DIR"
  ln -sf "$DIR/cbox" "$BIN_DIR/cbox"
  echo "Linked $BIN_DIR/cbox -> $DIR/cbox"

  ensure_bin_on_path "$HOME/.bashrc"
  ensure_bin_on_path "$HOME/.zshrc"
  echo
  if command -v cbox >/dev/null 2>&1; then
    echo "Done. 'cbox' is on your PATH now — run it from any project folder."
  else
    echo "Done. Open a new terminal (or 'source ~/.zshrc' / 'source ~/.bashrc'),"
    echo "then run 'cbox' from any project folder."
  fi
else
  echo "Skipped symlink/PATH changes. Run cbox via: $DIR/cbox"
fi

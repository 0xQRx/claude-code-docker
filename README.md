# claude-box

A lightweight, filesystem-sandboxed container for running Claude Code on your
host machine. Claude can read/write **only the folder you launch it in** — the
rest of the host filesystem is invisible to the container.

Two ways to use the same image:

- **`cbox`** — terminal launcher. `cd` into any project and run it.
- **`.devcontainer/`** — VS Code "Reopen in Container".

Both share `Dockerfile`, `init-firewall.sh`, and the same persistence volumes,
so you log in once.

## Quick start (CLI)

One-shot install — builds the image and puts `cbox` on your PATH:

```bash
./build.sh           # build image + symlink cbox into ~/.local/bin
```

Open a new terminal (or `source ~/.zshrc`), then from any project folder:

```bash
cd ~/code/my-project
cbox                 # launch Claude in this folder's sandbox
cbox --resume        # extra args forward straight to claude
cbox --shell         # drop into a zsh shell in the sandbox instead
cbox --tmux          # tmux session running Claude (prefix+c for more windows)
cbox --locked        # same, but with the egress allowlist firewall on
cbox --rebuild       # rebuild the image (e.g. to bump Claude version)
cbox -- <cmd...>     # run an arbitrary command in the sandbox
```

### Multiple Claude windows

`cbox --tmux` opens a tmux session (`main`) with Claude in window 0. Inside it:

- `Ctrl-b c` — new window (a zsh shell; run `claude` again for a second agent)
- `Ctrl-b n` / `Ctrl-b p` — next / previous window
- `Ctrl-b "` / `Ctrl-b %` — split the pane horizontally / vertically
- `Ctrl-b d` — detach (the session keeps running as long as the container does)

The session lives inside the container, so it disappears when you exit `cbox`.

`build.sh` is idempotent (re-running won't duplicate PATH entries) and supports
`--no-build`, `--no-path`, and `-- <docker build args>`.

## What is and isn't isolated

| Thing | Behavior |
|---|---|
| Current folder (`$PWD`) | Bind-mounted read/write at `/workspace`. |
| Rest of host filesystem | **Not mounted** — invisible to the container. |
| Login / auth | Persisted in the `claude-box-config` Docker volume. |
| Shell + command history | Persisted in the `claude-box-history` Docker volume. |
| File ownership | Files Claude creates are owned by **your** host user (UID/GID mapped). |
| Network | Open by default; `--locked` restricts egress to an allowlist. |

## Network modes

- **default** — full outbound network. Filesystem is still fully sandboxed.
- **`--locked`** — applies `init-firewall.sh`: only GitHub, npm, the Anthropic
  API, and a few telemetry endpoints are reachable. Adds `NET_ADMIN`/`NET_RAW`.

## Optional: git identity / SSH

By design, your host `~/.gitconfig` and SSH keys are **not** mounted (that would
break the "only this folder" guarantee). If you need to commit/push from inside
the sandbox, add mounts to `cbox` explicitly, e.g.:

```bash
-v "$HOME/.gitconfig:/home/node/.gitconfig:ro"
-v "$HOME/.ssh:/home/node/.ssh:ro"
```

## MCP servers

MCP **configuration** persists; MCP server **binaries** may not. When you run
`claude mcp add`, only the config (how to launch the server) is written:

| Scope | Stored in | Persists? |
|---|---|---|
| `--scope project` | `.mcp.json` in your repo | ✅ lives in the mounted `$PWD` (on the host). |
| `--scope local` (default) | `CLAUDE_CONFIG_DIR` (`/home/node/.claude`) | ✅ `claude-box-config` volume. |
| `--scope user` | `CLAUDE_CONFIG_DIR` (`/home/node/.claude`) | ✅ `claude-box-config` volume. |

The catch is the server **runtime**, not the config:

- **`npx`-based servers** (e.g. `npx -y @modelcontextprotocol/server-filesystem`)
  are re-fetched on each launch. They work fine, but need network — under
  `--locked` the npm registry is allowlisted, so this still works.
- **Globally installed servers** (`npm install -g some-mcp`) land in an image
  layer, which is **ephemeral with `--rm`** and gone next run. To make those
  durable, add a `RUN npm install -g ...` line to the `Dockerfile` and
  `cbox --rebuild`.

Rule of thumb: config persists automatically; prefer `npx`-style servers, or
bake heavyweight servers into the `Dockerfile`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Shared image (Node 20 + Claude Code + tooling). |
| `cbox` | Host launcher script. |
| `cbox-entrypoint.sh` | Root entrypoint: UID-map → firewall → drop to `node`. |
| `init-firewall.sh` | Egress allowlist (used by `--locked` and the devcontainer). |
| `.devcontainer/devcontainer.json` | VS Code path. |
# claude-code-docker

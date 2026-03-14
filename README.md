# clode — Claude Code in Docker

Run [Claude Code](https://claude.ai/code) in a hardened Docker container with a single command. Your project files are mounted read-write; your SSH keys are mounted read-only; nothing else leaks out.

> **This repo contains two independent tools:**
> - **`clode`** — the core Docker wrapper for Claude Code (no extra dependencies)
> - **`cws-tui`** — an optional terminal UI for managing multiple clode workspaces ([jump to cws-tui docs](#cws-tui--workspace-tui-optional))
>
> You can use `clode` without `cws-tui`. Install `cws-tui` only if you work across several projects simultaneously and want a visual overview.

## What is this?

Claude Code normally runs with full access to your machine. `clode` wraps it in a Docker container with:

- **No new privileges** (`--security-opt=no-new-privileges`)
- **All Linux capabilities dropped** (`--cap-drop=ALL`)
- **Resource limits** (4 GB RAM, 2 CPUs by default)
- **Minimal volume mounts** — only your project, `~/.claude`, and `~/.ssh` (read-only)
- **Your UID/GID** passed through so files are owned by you, not root
- **Automatic port forwarding** — container ports are mapped to free host ports so Claude-started servers are immediately accessible

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine on Linux)
- Python 3 (used for free-port detection — ships with macOS)
- A Claude OAuth token — see [Get your token](#get-your-token)

## Install

```bash
git clone https://github.com/kartik-solvative/clode.git ~/Projects/clode
cd ~/Projects/clode
./install.sh
source ~/.zshrc
```

`install.sh` will ask for:

| Setting | Default | Description |
|---|---|---|
| Workspace directory | `~/Projects` | Where your projects live — used by `clode list` |
| Docker image | `claude-code:latest` | The image to run |
| Idle timeout | `3600` (1 hour) | Auto-stop background containers after N seconds of inactivity (0 = disabled) |
| Expose ports | `3000,5173,8080,8888` | Container ports to auto-forward to dynamic host ports on every start |

Settings are saved to `~/.clode.config`. Running `install.sh` again is safe — it detects an existing install and skips prompts unless you pass `--reconfigure`.

## Get your token

`CLAUDE_CODE_OAUTH_TOKEN` is the OAuth token Claude Code stores after you log in. To get it:

1. Install Claude Code on your host machine (one-time):
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
2. Log in:
   ```bash
   claude
   ```
3. Extract the token:
   ```bash
   jq -r '.claudeAiOauth.oauth_token' ~/.claude/.credentials.json
   ```
4. Export it (add to `~/.zshrc` to make it permanent):
   ```bash
   export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
   ```

> You only need Claude Code installed on your host to get the token. Once `clode` is set up, all actual Claude usage runs inside Docker.

## Commands

### `clode` — smart default

```bash
clode [flags] [prompt]
```

If a container is already running for the current directory, attaches to it. Otherwise starts a new interactive session. Always tells you what it did.

### `clode start`

```bash
clode start [--bg] [--resume] [--memory <mem>] [--cpus <n>] [-p <host:container>] [prompt]
```

Explicitly start a new session. Errors if a container already exists.

| Flag | Description |
|---|---|
| `--bg` | Run detached in the background |
| `--resume` | Resume the last conversation |
| `--memory <mem>` | Override memory limit (e.g. `8g`) |
| `--cpus <n>` | Override CPU limit |
| `-p <map>` | Add an extra port mapping beyond `CLODE_EXPOSE_PORTS` (repeatable) |

On start, clode prints the live port mappings:

```
clode: starting 'my-app'
  http://localhost:54231  →  container port 3000
  http://localhost:54232  →  container port 5173
```

Claude inside the container receives `CLODE_PORT_3000=54231` etc. as environment variables, so it knows which host URLs to report to you.

### `clode new`

```bash
clode new [label]
```

Start a new container in the current project directory alongside any already-running sessions. The new container gets an auto-numbered name (`myproject-2`, `myproject-3`, …) or a labeled name if supplied.

```bash
clode new                  # auto-named: myproject-2
clode new fix-auth         # labeled: myproject--fix-auth
clode new --bg "run tests" # background, no label
```

When 2 or more sessions are running, `clode`, `clode attach`, and `clode stop` show a numbered picker to choose which session to interact with.

### `clode attach`

```bash
clode attach
```

Attach to the running container for the current directory. Errors if none is running. Shows a numbered picker when multiple sessions are running.

### `clode stop`

```bash
clode stop
```

Stop and remove the container for the current directory.

### `clode list`

```bash
clode list
```

Show all projects in your workspace and their container status, including live port mappings:

```
PROJECT                        CONTAINER            STATUS
-------                        ---------            ------
my-app                         my-app               running
                               http://localhost:54231 → container:3000
other-project                  -                    stopped
```

### `clode update`

```bash
clode update [--reconfigure]
```

Pull the latest Docker image and re-run the shell wiring. Pass `--reconfigure` to change config settings.

### `clode help`

```bash
clode help
clode -h
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Yes | Your Claude OAuth token |
| `NTFY_TOPIC` | No | [ntfy.sh](https://ntfy.sh) topic — sends a notification when a background container finishes |

## Injecting secrets

clode injects environment variables from two files automatically:

| File | Scope |
|---|---|
| `~/.clode.env` | Global — injected into every container |
| `.env` in project root | Project-specific — injected if the file exists |

Only lines matching `KEY=VALUE` format are injected. Blank lines and `#` comments are ignored.

## Multiple projects

Each project gets its own container named after the directory. You can run as many simultaneously as you like — port conflicts are avoided because host ports are dynamically assigned on each `clode start`.

```bash
cd ~/Projects/api     && clode start --bg
cd ~/Projects/web     && clode start --bg
cd ~/Projects/worker  && clode start --bg
clode list            # see all three with their port mappings
```

## Security model

| Control | Setting | Effect |
|---|---|---|
| `--security-opt=no-new-privileges` | Enforced | Process cannot gain new privileges via setuid/setgid |
| `--cap-drop=ALL` | Enforced | All Linux capabilities removed |
| `--memory=4g` | Default | Container OOM-killed if it exceeds limit |
| `--cpus=2` | Default | Container throttled to 2 CPU cores |
| SSH keys | `:ro` | Mounted read-only — Claude can use keys but cannot modify them |
| Network | Default bridge | Outbound internet only (needed for Claude API calls) |

## Updating

```bash
clode update
source ~/.zshrc
```

Or to change settings at the same time:

```bash
clode update --reconfigure
source ~/.zshrc
```

---

## cws-tui — Workspace TUI (optional)

`cws-tui` is a standalone terminal UI for managing multiple clode workspaces at once. It is **not required** to use `clode` — install it only if you want a visual dashboard across projects.

```
┌─ workspaces ──────────────┬─ focusreader › main › clode-1 ──────────────────┐
│ ▼ focusreader             │ live preview · 2s                                │
│   ▼ main                  │                                                  │
│     ● host-1              │ $ claude --dangerously-skip-permissions          │
│     ● clode-1             │ ✻ Thinking…                                      │
│ ▶ payments-api            │                                                  │
│ ▶ my-webapp [no session]  │ ↵ jump into this terminal                        │
└───────────────────────────┴──────────────────────────────────────────────────┘
  ↑↓ navigate  ·  ↵ jump in  ·  Ctrl+A action  ·  space palette  ·  q quit
```

### What it does

- Shows all your projects (git repos in `~/Projects/`) in a tree view
- Green dot = terminal running · Yellow dot = clode container detached · no dot = stopped
- Right pane shows a live capture of the selected terminal, refreshed every 2 seconds
- Jump directly into any terminal with Enter; detach back with `Ctrl+b d`
- Ctrl+A opens a context-sensitive action menu: new terminal, new worktree, fg a detached container, kill a project

### Install cws-tui

Requires [Go](https://go.dev/dl/) 1.16+.

```bash
# from the clode repo directory
make install
```

This builds the binary and copies it to `~/bin/cws-tui`. Make sure `~/bin` is in your `PATH`.

Or build manually:

```bash
go build -o ~/bin/cws-tui ./cmd/cws-tui
```

### Run

```bash
cws-tui
```

| Env var | Default | Description |
|---|---|---|
| `CWS_PROJECTS_DIR` | `~/Projects` | Directory scanned for git repos |
| `CWS_SELECT_PROJECT` | — | Pre-select and expand a project on startup |
| `CWS_SCRIPT` | `~/Projects/clode/clode-ws.sh` | Path to `clode-ws.sh` (for shell actions) |
| `_CLODE_WS_ACTION_KEY` | `Ctrl+A` | Override the action menu trigger key |

### Keyboard reference

| Key | Action |
|---|---|
| `↑` `↓` | Navigate the tree |
| `→` `←` | Expand / collapse a node |
| `Enter` | Jump into terminal · expand project · create session if none |
| `Ctrl+A` | Open action menu for the selected node |
| `Space` | Open fuzzy command palette |
| `q` | Quit |

**Action menu (`Ctrl+A`) keys**

| Key | Action |
|---|---|
| `n` | New host terminal in this worktree |
| `c` | New clode terminal in this worktree |
| `w` | New git worktree (prompts for branch name) |
| `f` | Foreground a detached clode container |
| `d` | Delete terminal |
| `D` | Delete worktree |
| `X` | Kill project (all sessions + containers) |
| `Esc` | Cancel |

### Relationship to clode

`cws-tui` reads tmux session names and Docker container names that follow the `cws-*` convention used by `clode-ws.sh`. It does not depend on any clode internals and does not need to run inside a Docker container — it runs on your host machine, alongside clode.

```
clode          — runs Claude Code in Docker, one project at a time
clode-ws.sh    — shell helpers: multi-worktree sessions, window naming
cws-tui        — visual overview of everything clode-ws manages
```

---

## Troubleshooting

**`clode: command not found`** — run `source ~/.zshrc` after install.

**`container already exists`** — run `clode stop` first, or `docker rm <name>`.

**Port not accessible** — check `clode list` for the correct host port. Claude-started servers bind to container-side ports (e.g. 3000); the mapped host port is shown on start and in `clode list`.

**Token not set** — make sure `CLAUDE_CODE_OAUTH_TOKEN` is exported before running `clode`.

**`clode update` can't find install.sh`** — this can happen if `clode.sh` was sourced from a symlink. Run `bash ~/Projects/clode/install.sh` directly instead.

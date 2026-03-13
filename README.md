# clode — Claude Code in Docker

Run [Claude Code](https://claude.ai/code) in a hardened Docker container with a single command. Your project files are mounted read-write; your SSH keys are mounted read-only; nothing else leaks out.

## What is this?

Claude Code normally runs with full access to your machine. `clode` wraps it in a Docker container with:

- **No new privileges** (`--security-opt=no-new-privileges`)
- **All Linux capabilities dropped** (`--cap-drop=ALL`)
- **Resource limits** (4 GB RAM, 2 CPUs)
- **Minimal volume mounts** — only your project, `~/.claude`, and `~/.ssh` (read-only)
- **Your UID/GID** passed through so files are owned by you, not root

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine on Linux)
- A Claude OAuth token — set as `CLAUDE_CODE_OAUTH_TOKEN` in your environment

## Install

```bash
git clone https://github.com/YOUR_USERNAME/clode.git ~/Projects/clode
cd ~/Projects/clode
./install.sh
source ~/.zshrc
```

`install.sh` does two things:
1. Builds the `claude-code:latest` Docker image
2. Adds `source ".../clode.sh"` to your `~/.zshrc`

It is **idempotent** — safe to run again after `git pull`.

## Set your token

```bash
export CLAUDE_CODE_OAUTH_TOKEN=<your-token>
```

Add this to `~/.zshrc` (or `~/.bash_profile`) to make it permanent.

## Commands

| Command | What it does |
|---|---|
| `clode` | Start Claude Code interactively in the current directory |
| `clode-resume` | Resume the last Claude session in the current directory |
| `clode-bg` | Start Claude Code in the background (detached) |
| `clode-attach` | Attach to a running background container |
| `clode-stop` | Stop and remove the container for the current directory |
| `clode-list` | List all running clode containers |
| `clode-logs` | Tail logs from the background container |

All commands use the current directory name as the container name, so you can run one container per project simultaneously.

## Usage example

```bash
cd ~/Projects/my-app
clode                         # interactive session
clode-bg "fix the login bug"  # background task
clode-attach                  # check in on it
clode-logs                    # tail output
clode-stop                    # clean up
```

## Security model

| Control | Setting | Effect |
|---|---|---|
| `--security-opt=no-new-privileges` | Enforced | Process cannot gain new Linux privileges via setuid/setgid |
| `--cap-drop=ALL` | Enforced | All Linux capabilities removed (no raw sockets, no mount, etc.) |
| `--memory=4g` | Enforced | Container OOM-killed if it exceeds 4 GB |
| `--cpus=2` | Enforced | Container throttled to 2 CPU cores |
| SSH keys | `:ro` | Mounted read-only — Claude can use keys but cannot modify them |
| Network | Default bridge | Container has outbound internet (needed for Claude API calls) |

## Updating

```bash
cd ~/Projects/clode
git pull
./install.sh   # rebuilds the image; skips shell wiring (idempotent)
source ~/.zshrc
```

## Troubleshooting

**`clode: command not found`** — run `source ~/.zshrc` after install.

**`Error response from daemon: Conflict`** — a container with that name already exists. Run `clode-stop` first, or `docker rm <name>`.

**Token not set** — make sure `CLAUDE_CODE_OAUTH_TOKEN` is exported before running `clode`.

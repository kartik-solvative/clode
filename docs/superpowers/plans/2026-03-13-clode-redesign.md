# Clode Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign clode into a clean subcommand CLI with smart defaults, env var injection, workspace-aware project listing, idle timeout, and idempotent install/update.

**Architecture:** A single `clode()` shell function in `clode.sh` dispatches to subcommand handlers. Config lives in `~/.clode.config` (sourced shell file). `install.sh` is idempotent — detects existing installs and merges config. Env vars are injected from `~/.clode.env` (global) and `.env` in the project root (project-specific).

**Tech Stack:** bash/zsh, Docker, shellcheck (linting), bats-core (testing)

---

## Chunk 1: Config & Install

### Task 1: `~/.clode.config` schema + install.sh

**Files:**
- Modify: `install.sh`

The config file is a sourced shell script:

```sh
# ~/.clode.config
CLODE_WORKSPACE="$HOME/Projects"
CLODE_IMAGE="claude-code:latest"
CLODE_IDLE_TIMEOUT=3600   # seconds; 0 = disabled
```

- [ ] **Step 1: Read existing `install.sh`**

```bash
cat install.sh
```

- [ ] **Step 2: Rewrite `install.sh` to be idempotent**

Replace contents with:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.clode.config"
ZSHRC="$HOME/.zshrc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_load_config() {
  [[ -f "$CONFIG" ]] && source "$CONFIG"
}

_save_config() {
  cat >"$CONFIG" <<EOF
CLODE_WORKSPACE="${CLODE_WORKSPACE}"
CLODE_IMAGE="${CLODE_IMAGE:-claude-code:latest}"
CLODE_IDLE_TIMEOUT="${CLODE_IDLE_TIMEOUT:-3600}"
EOF
}

_ask() {
  local prompt="$1" default="$2" var="$3"
  read -rp "${prompt} [${default}]: " input
  eval "${var}=\"${input:-${default}}\""
}

_add_to_shell() {
  local line="source \"${SCRIPT_DIR}/clode.sh\""
  if ! grep -qF "$line" "$ZSHRC" 2>/dev/null; then
    echo "" >> "$ZSHRC"
    echo "# clode" >> "$ZSHRC"
    echo "$line" >> "$ZSHRC"
    echo "Added clode to $ZSHRC"
  else
    echo "clode already in $ZSHRC — skipping"
  fi
}

main() {
  local reconfigure=0
  [[ "${1:-}" == "--reconfigure" ]] && reconfigure=1

  _load_config

  if [[ -f "$CONFIG" && $reconfigure -eq 0 ]]; then
    echo "clode is already installed."
    echo "  Workspace : ${CLODE_WORKSPACE}"
    echo "  Image     : ${CLODE_IMAGE:-claude-code:latest}"
    echo "  Idle timeout: ${CLODE_IDLE_TIMEOUT:-3600}s"
    echo ""
    echo "Run with --reconfigure to change settings."
    _add_to_shell
    return 0
  fi

  echo "=== clode install ==="
  _ask "Projects workspace directory" "${CLODE_WORKSPACE:-$HOME/Projects}" CLODE_WORKSPACE
  _ask "Docker image" "${CLODE_IMAGE:-claude-code:latest}" CLODE_IMAGE
  _ask "Idle timeout in seconds (0 to disable)" "${CLODE_IDLE_TIMEOUT:-3600}" CLODE_IDLE_TIMEOUT

  # Expand ~ in workspace path
  CLODE_WORKSPACE="${CLODE_WORKSPACE/#\~/$HOME}"

  _save_config
  _add_to_shell

  echo ""
  echo "Done. Run: source ~/.zshrc"
}

main "$@"
```

- [ ] **Step 3: Make install.sh executable**

```bash
chmod +x install.sh
```

- [ ] **Step 4: Run shellcheck**

```bash
shellcheck install.sh
```

Expected: no errors or warnings.

- [ ] **Step 5: Test fresh install (dry run)**

```bash
# Temporarily back up config if it exists
[[ -f ~/.clode.config ]] && cp ~/.clode.config ~/.clode.config.bak
rm -f ~/.clode.config
bash install.sh
cat ~/.clode.config
# Restore
[[ -f ~/.clode.config.bak ]] && mv ~/.clode.config.bak ~/.clode.config
```

Expected: prompts for workspace, image, timeout; writes `~/.clode.config`.

- [ ] **Step 6: Test idempotent re-run**

```bash
bash install.sh
```

Expected: prints current config, says "already installed", no prompts.

- [ ] **Step 7: Test --reconfigure**

```bash
bash install.sh --reconfigure
```

Expected: prompts again with current values as defaults.

- [ ] **Step 8: Commit**

```bash
git add install.sh
git commit -m "feat: rewrite install.sh as idempotent configurator"
```

---

## Chunk 2: Core Dispatcher + Env Var Injection

### Task 2: Rewrite `clode.sh` — config loading + env injection helpers

**Files:**
- Modify: `clode.sh`

- [ ] **Step 1: Rewrite clode.sh top — config loading + helpers**

Replace the entire file with this foundation (helpers only, no commands yet):

```bash
# Claude Code in Docker — source this file from ~/.zshrc

# ── Config ────────────────────────────────────────────────
_CLODE_CONFIG="$HOME/.clode.config"
_CLODE_HOME="$HOME"

_clode_load_config() {
  [[ -f "$_CLODE_CONFIG" ]] && source "$_CLODE_CONFIG"
  CLODE_IMAGE="${CLODE_IMAGE:-claude-code:latest}"
  CLODE_IDLE_TIMEOUT="${CLODE_IDLE_TIMEOUT:-3600}"
  CLODE_WORKSPACE="${CLODE_WORKSPACE:-$HOME/Projects}"
}

# ── Env var injection ─────────────────────────────────────
# Builds a list of -e KEY=VALUE args from a .env file.
# Skips blank lines and comments.
_clode_env_file_args() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Only accept KEY=VALUE lines
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      echo "-e $(printf '%q' "$line")"
    fi
  done < "$file"
}

_clode_all_env_args() {
  _clode_env_file_args "$HOME/.clode.env"
  _clode_env_file_args "$(pwd)/.env"
}

# ── Base docker args ──────────────────────────────────────
_clode_base_args() {
  local name="$1"
  local memory="${2:-4g}"
  local cpus="${3:-2}"
  echo "--rm \
    -u $(id -u):$(id -g) \
    -e HOME=${_CLODE_HOME} \
    -e CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN} \
    $(_clode_all_env_args) \
    -v ${_CLODE_HOME}/.claude:${_CLODE_HOME}/.claude \
    -v ${_CLODE_HOME}/.claude.json:${_CLODE_HOME}/.claude.json \
    -v ${_CLODE_HOME}/.ssh:${_CLODE_HOME}/.ssh:ro \
    -v $(pwd):/workspace \
    --name ${name} \
    --label clode.workspace=$(pwd) \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --memory=${memory} \
    --cpus=${cpus}"
}

# ── Helpers ───────────────────────────────────────────────
_clode_name()       { basename "$(pwd)"; }
_clode_is_running() { docker ps -q --filter "name=^$1$" | grep -q .; }
_clode_exists()     { docker ps -aq --filter "name=^$1$" | grep -q .; }
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck clode.sh
```

Expected: no errors.

- [ ] **Step 3: Source and verify helpers load**

```bash
source clode.sh
type _clode_load_config
```

Expected: prints function definition.

- [ ] **Step 4: Commit**

```bash
git add clode.sh
git commit -m "feat: add config loading and env injection helpers to clode.sh"
```

---

### Task 3: `clode help` + `_clode_help()`

**Files:**
- Modify: `clode.sh`

- [ ] **Step 1: Add `_clode_help` function after helpers**

```bash
_clode_help() {
  cat <<'EOF'
clode — Claude Code in Docker

USAGE
  clode [flags] [prompt]     Smart start: attach if running, else start
  clode <subcommand> [args]

SUBCOMMANDS
  start [--bg] [prompt]  Explicitly start a new session
  attach                 Attach to running container (error if none)
  stop                   Stop and remove current project's container
  list                   List all projects and container status
  update [--reconfigure] Pull latest image, update shell config
  help                   Show this help message

FLAGS (start / default run)
  --bg            Run in background (non-interactive)
  --resume        Resume last conversation
  --memory <mem>  Memory limit (default: 4g)
  --cpus <n>      CPU limit (default: 2)
  -h, --help      Show this help message

ENVIRONMENT FILES
  ~/.clode.env    Global env vars — always injected
  ./.env          Project env vars — injected if present

EXAMPLES
  clode                        Start or attach (smart default)
  clode start                  Explicitly start new session
  clode start --bg "fix tests" Run task in background
  clode attach                 Attach to running session
  clode stop                   Stop current project's container
  clode list                   Show all projects and status
  clode update                 Pull latest image
  clode update --reconfigure   Update + change settings
EOF
}
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck clode.sh
```

- [ ] **Step 3: Commit**

```bash
git add clode.sh
git commit -m "feat: add clode help text"
```

---

### Task 4: `clode start` + idle timeout

**Files:**
- Modify: `clode.sh`

- [ ] **Step 1: Add `_clode_start` function**

```bash
_clode_start() {
  _clode_load_config
  local name
  name=$(_clode_name)
  local bg=0 resume=0 memory="4g" cpus="2"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg)        bg=1;        shift ;;
      --resume)    resume=1;    shift ;;
      --memory)    memory="$2"; shift 2 ;;
      --cpus)      cpus="$2";   shift 2 ;;
      *)           break ;;
    esac
  done

  if _clode_exists "$name"; then
    echo "clode: container '$name' already exists — use 'clode attach' or 'clode stop' first." >&2
    return 1
  fi

  local claude_flags="--dangerously-skip-permissions"
  [[ $resume -eq 1 ]] && claude_flags="$claude_flags --resume"

  local base_args
  base_args=$(_clode_base_args "$name" "$memory" "$cpus")

  if [[ $bg -eq 1 ]]; then
    eval docker run -d $base_args "$CLODE_IMAGE" $claude_flags "$@"
    echo "clode: started '$name' in background"

    # Idle timeout watcher
    if [[ "${CLODE_IDLE_TIMEOUT:-0}" -gt 0 ]]; then
      (
        sleep "$CLODE_IDLE_TIMEOUT"
        if _clode_is_running "$name"; then
          docker stop "$name" >/dev/null 2>&1 && \
            echo "clode: '$name' stopped after idle timeout (${CLODE_IDLE_TIMEOUT}s)"
        fi
      ) &
      disown
    fi

    # ntfy notification
    if [[ -n "${NTFY_TOPIC:-}" ]]; then
      (docker wait "$name" >/dev/null 2>&1 && \
        curl -s -o /dev/null "https://ntfy.sh/${NTFY_TOPIC}" \
          -H "Title: clode done" \
          -H "Tags: white_check_mark" \
          -d "$name finished") &
      disown
    fi
  else
    echo "clode: starting '$name'"
    eval docker run -it $base_args "$CLODE_IMAGE" $claude_flags "$@"
  fi
}
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck clode.sh
```

- [ ] **Step 3: Commit**

```bash
git add clode.sh
git commit -m "feat: add clode start with bg mode and idle timeout"
```

---

### Task 5: `clode attach`

**Files:**
- Modify: `clode.sh`

- [ ] **Step 1: Add `_clode_attach` function**

```bash
_clode_attach() {
  local name
  name=$(_clode_name)

  if ! _clode_is_running "$name"; then
    echo "clode: no running container for '$(pwd)'." >&2
    echo "       Run 'clode start' to begin a session." >&2
    return 1
  fi

  echo "clode: attaching to '$name'"
  docker exec -it "$name" claude --dangerously-skip-permissions --resume
}
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck clode.sh
```

- [ ] **Step 3: Commit**

```bash
git add clode.sh
git commit -m "feat: add clode attach"
```

---

### Task 6: `clode stop`

**Files:**
- Modify: `clode.sh`

- [ ] **Step 1: Add `_clode_stop` function**

```bash
_clode_stop() {
  local name
  name=$(_clode_name)

  if ! _clode_exists "$name"; then
    echo "clode: no container found for '$(pwd)'." >&2
    return 1
  fi

  docker stop "$name" >/dev/null && docker rm "$name" >/dev/null 2>&1 || true
  echo "clode: stopped '$name'"
}
```

- [ ] **Step 2: Run shellcheck + commit**

```bash
shellcheck clode.sh
git add clode.sh
git commit -m "feat: add clode stop"
```

---

### Task 7: `clode list`

**Files:**
- Modify: `clode.sh`

`clode list` scans `$CLODE_WORKSPACE` for direct subdirectories and checks each for a running container. Uses the `clode.workspace` label set in `_clode_base_args`.

- [ ] **Step 1: Add `_clode_list` function**

```bash
_clode_list() {
  _clode_load_config

  if [[ ! -d "$CLODE_WORKSPACE" ]]; then
    echo "clode: workspace '$CLODE_WORKSPACE' not found." >&2
    return 1
  fi

  # Build a map of workspace_path -> container_name from running containers
  declare -A running_map
  while IFS='|' read -r cname wspath; do
    [[ -n "$wspath" ]] && running_map["$wspath"]="$cname"
  done < <(docker ps --filter "label=clode.workspace" \
    --format '{{.Names}}|{{.Label "clode.workspace"}}' 2>/dev/null)

  printf "%-30s %-20s %s\n" "PROJECT" "CONTAINER" "STATUS"
  printf "%-30s %-20s %s\n" "-------" "---------" "------"

  for dir in "$CLODE_WORKSPACE"/*/; do
    [[ -d "$dir" ]] || continue
    local project
    project=$(basename "$dir")
    local abspath
    abspath=$(cd "$dir" && pwd)
    local cname="${running_map[$abspath]:-}"

    if [[ -n "$cname" ]]; then
      local status
      status=$(docker inspect --format '{{.State.Status}}' "$cname" 2>/dev/null || echo "unknown")
      printf "%-30s %-20s %s\n" "$project" "$cname" "$status"
    else
      printf "%-30s %-20s %s\n" "$project" "-" "stopped"
    fi
  done
}
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck clode.sh
```

- [ ] **Step 3: Commit**

```bash
git add clode.sh
git commit -m "feat: add clode list with workspace scanning"
```

---

### Task 8: `clode update`

**Files:**
- Modify: `clode.sh`
- Reference: `install.sh`

- [ ] **Step 1: Add `_clode_update` function**

```bash
_clode_update() {
  _clode_load_config
  local reconfigure=0
  [[ "${1:-}" == "--reconfigure" ]] && reconfigure=1

  echo "clode: pulling latest image (${CLODE_IMAGE})..."
  docker pull "$CLODE_IMAGE"

  # Re-run install for config update / shell re-sourcing
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ $reconfigure -eq 1 ]]; then
    bash "${script_dir}/install.sh" --reconfigure
  else
    bash "${script_dir}/install.sh"
  fi

  echo "clode: updated. Run: source ~/.zshrc"
}
```

- [ ] **Step 2: Run shellcheck + commit**

```bash
shellcheck clode.sh
git add clode.sh
git commit -m "feat: add clode update"
```

---

### Task 9: Main `clode()` dispatcher

**Files:**
- Modify: `clode.sh`

This is the single entry point. It routes subcommands and implements the smart default (attach if running, else start).

- [ ] **Step 1: Add main `clode()` function**

```bash
clode() {
  case "${1:-}" in
    -h|--help|help)
      _clode_help
      return 0
      ;;
    start)
      shift
      _clode_start "$@"
      ;;
    attach)
      _clode_attach
      ;;
    stop)
      _clode_stop
      ;;
    list)
      _clode_list
      ;;
    update)
      shift
      _clode_update "${1:-}"
      ;;
    *)
      # Smart default: attach if running, else start
      local name
      name=$(_clode_name)
      if _clode_is_running "$name"; then
        echo "clode: container '$name' is running — attaching"
        _clode_attach
      else
        echo "clode: no running container — starting new session"
        _clode_start "$@"
      fi
      ;;
  esac
}
```

- [ ] **Step 2: Run shellcheck on full file**

```bash
shellcheck clode.sh
```

Expected: no errors.

- [ ] **Step 3: Source and smoke test**

```bash
source clode.sh
clode help
clode list
```

- [ ] **Step 4: Commit**

```bash
git add clode.sh
git commit -m "feat: add main clode dispatcher with smart default"
```

---

## Chunk 3: Polish + Push

### Task 10: Remove `_clode_base_args` (now internal only) + final cleanup

**Files:**
- Modify: `clode.sh`

- [ ] **Step 1: Verify `_clode_base_args` is only called by `_clode_start`**

```bash
grep -n '_clode_base_args' clode.sh
```

Expected: defined once, called once in `_clode_start`.

- [ ] **Step 2: Run full shellcheck**

```bash
shellcheck clode.sh install.sh
```

Expected: clean.

- [ ] **Step 3: Manual end-to-end test checklist**

```
clode help               → prints help
clode list               → shows workspace projects
clode start              → starts new session (foreground)
clode                    → attaches (container running)
clode stop               → stops container
clode                    → starts new session (container gone)
clode start --bg "hello" → starts bg, idle timeout fires after config value
clode update             → pulls image, shows current config
clode update --reconfigure → prompts for new config values
```

- [ ] **Step 4: Final commit + push**

```bash
git add clode.sh install.sh
git commit -m "chore: final cleanup and shellcheck pass"
git push origin master
```

---

## Summary of Files

| File | Change |
|------|--------|
| `clode.sh` | Full rewrite — single dispatcher, all subcommands, env injection, idle timeout |
| `install.sh` | Full rewrite — idempotent, writes `~/.clode.config`, adds shell source line |

## Config Schema (`~/.clode.config`)

```sh
CLODE_WORKSPACE="$HOME/Projects"
CLODE_IMAGE="claude-code:latest"
CLODE_IDLE_TIMEOUT=3600
```

## Env Injection Order

1. `~/.clode.env` — global secrets
2. `./.env` — project-specific (injected if file exists in current directory)
3. `CLAUDE_CODE_OAUTH_TOKEN` — always injected explicitly

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
# Builds -e KEY=VALUE args from a .env file.
# Skips blank lines and comments.
_clode_env_file_args() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      printf -- '-e\n%s\n' "$line"
    fi
  done < "$file"
}

_clode_all_env_args() {
  _clode_env_file_args "$HOME/.clode.env"
  _clode_env_file_args "$(pwd)/.env"
}

# ── Base docker args ──────────────────────────────────────
# Outputs one docker-arg token per line. Callers MUST consume with mapfile:
#   mapfile -t _args < <(_clode_base_args "$name" "$memory" "$cpus")
#   docker run "${_args[@]}" ...
# Do NOT use: eval docker run $(_clode_base_args ...) — word-splitting will corrupt paths with spaces.
_clode_base_args() {
  local name="$1"
  local memory="${2:-4g}"
  local cpus="${3:-2}"
  # Ensure ~/.claude.json exists as a file (Docker would create a dir if missing)
  touch "$_CLODE_HOME/.claude.json" 2>/dev/null || true
  printf -- '--rm\n'
  printf -- '-u %s\n' "$(id -u):$(id -g)"
  printf -- '-e HOME=%s\n' "$_CLODE_HOME"
  printf -- '-e CLAUDE_CODE_OAUTH_TOKEN=%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}"
  _clode_all_env_args
  printf -- '-v %s:%s\n' "$_CLODE_HOME/.claude" "$_CLODE_HOME/.claude"
  printf -- '-v %s:%s\n' "$_CLODE_HOME/.claude.json" "$_CLODE_HOME/.claude.json"
  printf -- '-v %s:%s:ro\n' "$_CLODE_HOME/.ssh" "$_CLODE_HOME/.ssh"
  printf -- '-v %s:/workspace\n' "$(pwd)"
  printf -- '--name %s\n' "$name"
  printf -- '--label clode.workspace=%s\n' "$(pwd)"
  printf -- '--security-opt=no-new-privileges\n'
  printf -- '--cap-drop=ALL\n'
  printf -- '--memory=%s\n' "$memory"
  printf -- '--cpus=%s\n' "$cpus"
}

# ── Helpers ───────────────────────────────────────────────
_clode_name()       { basename "$(pwd)"; }
_clode_is_running() { docker ps -q --filter "name=^${1}$" 2>/dev/null | grep -q .; }
_clode_exists()     { docker ps -aq --filter "name=^${1}$" 2>/dev/null | grep -q .; }

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

_clode_start() {
  _clode_load_config
  local name
  name=$(_clode_name)
  local bg=0 resume=0 memory="4g" cpus="2"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg)       bg=1;        shift ;;
      --resume)   resume=1;    shift ;;
      --memory)   memory="$2"; shift 2 ;;
      --cpus)     cpus="$2";   shift 2 ;;
      *)          break ;;
    esac
  done

  if _clode_exists "$name"; then
    echo "clode: container '$name' already exists — use 'clode attach' or 'clode stop' first." >&2
    return 1
  fi

  local claude_flags="--dangerously-skip-permissions"
  [[ $resume -eq 1 ]] && claude_flags="$claude_flags --resume"

  mapfile -t _args < <(_clode_base_args "$name" "$memory" "$cpus")

  if [[ $bg -eq 1 ]]; then
    docker run -d "${_args[@]}" "$CLODE_IMAGE" $claude_flags "$@"
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
    docker run -it "${_args[@]}" "$CLODE_IMAGE" $claude_flags "$@"
  fi
}

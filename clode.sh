# Claude Code in Docker — source this file from ~/.zshrc

# ── Config ────────────────────────────────────────────────
_CLODE_CONFIG="$HOME/.clode.config"
_CLODE_HOME="$HOME"

_clode_load_config() {
  [[ -f "$_CLODE_CONFIG" ]] && source "$_CLODE_CONFIG"
  CLODE_IMAGE="${CLODE_IMAGE:-claude-code:latest}"
  CLODE_IDLE_TIMEOUT="${CLODE_IDLE_TIMEOUT:-3600}"
  CLODE_WORKSPACE="${CLODE_WORKSPACE:-$HOME/Projects}"
  CLODE_EXPOSE_PORTS="${CLODE_EXPOSE_PORTS:-3000,5173,8080,8888}"
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
# Outputs one docker-arg token per line. Callers MUST collect into an array:
#   local -a _args=()
#   while IFS= read -r _line; do [[ -n "$_line" ]] && _args+=("$_line"); done < <(_clode_base_args ...)
#   docker run "${_args[@]}" ...
# Do NOT use: eval docker run $(_clode_base_args ...) — word-splitting will corrupt paths with spaces.
_clode_base_args() {
  local name="$1"
  local memory="${2:-4g}"
  local cpus="${3:-2}"
  # Ensure ~/.claude.json exists as a file (Docker would create a dir if missing)
  touch "$_CLODE_HOME/.claude.json" 2>/dev/null || true
  printf -- '--rm\n'
  printf -- '-u\n%s\n' "$(id -u):$(id -g)"
  printf -- '-e\nHOME=%s\n' "$_CLODE_HOME"
  printf -- '-e\nCLAUDE_CODE_OAUTH_TOKEN=%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}"
  _clode_all_env_args
  printf -- '-v\n%s:%s\n' "$_CLODE_HOME/.claude" "$_CLODE_HOME/.claude"
  printf -- '-v\n%s:%s\n' "$_CLODE_HOME/.claude.json" "$_CLODE_HOME/.claude.json"
  printf -- '-v\n%s:%s:ro\n' "$_CLODE_HOME/.ssh" "$_CLODE_HOME/.ssh"
  # ~/.claude is already mounted above; just point the bridge at the Mac host
  # so PermissionRequest/Notification hooks reach Nod via host.docker.internal
  printf -- '-e\nNOD_HOST=host.docker.internal\n'
  printf -- '-v\n%s:/workspace\n' "$(pwd)"
  printf -- '--name\n%s\n' "$name"
  printf -- '--label\nclode.workspace=%s\n' "$(pwd)"
  printf -- '--security-opt=no-new-privileges\n'
  printf -- '--cap-drop=ALL\n'
  printf -- '--memory=%s\n' "$memory"
  printf -- '--cpus=%s\n' "$cpus"
}

# ── Helpers ───────────────────────────────────────────────
_clode_name()       { basename "$(pwd)"; }
_clode_is_running() { docker ps -q --filter "name=^${1}$" 2>/dev/null | grep -q .; }
_clode_exists()     { docker ps -aq --filter "name=^${1}$" 2>/dev/null | grep -q .; }

# Ask the OS for a free ephemeral port.
_clode_free_port() {
  python3 -c "import socket; s=socket.socket(); s.bind(('',0)); p=s.getsockname()[1]; s.close(); print(p)"
}

# Populate globals from CLODE_EXPOSE_PORTS:
#   _CLODE_PORT_ARGS   — docker -p host:container pairs
#   _CLODE_PORT_EXTRA  — -e CLODE_PORT_<n>=<host> and --label clode.port.<n>=<host>
#   _CLODE_PORT_LINES  — human-readable summary lines
_clode_build_port_args() {
  _CLODE_PORT_ARGS=()
  _CLODE_PORT_EXTRA=()
  _CLODE_PORT_LINES=()
  [[ -z "${CLODE_EXPOSE_PORTS:-}" ]] && return
  while IFS= read -r cport; do
    cport="${cport// /}"
    [[ -z "$cport" ]] && continue
    local hport
    hport=$(_clode_free_port)
    _CLODE_PORT_ARGS+=("-p" "${hport}:${cport}")
    _CLODE_PORT_EXTRA+=("-e" "CLODE_PORT_${cport}=${hport}")
    _CLODE_PORT_EXTRA+=("--label" "clode.port.${cport}=${hport}")
    _CLODE_PORT_LINES+=("  http://localhost:${hport}  →  container port ${cport}")
  done < <(tr ',' '\n' <<< "${CLODE_EXPOSE_PORTS}")
}

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
  --bg              Run in background (non-interactive)
  --resume          Resume last conversation
  -p, --port <map>  Publish a port (e.g. -p 3000:3000); repeatable
  --memory <mem>    Memory limit (default: 4g)
  --cpus <n>        CPU limit (default: 2)
  -h, --help        Show this help message

ENVIRONMENT FILES
  ~/.clode.env    Global env vars — always injected
  ./.env          Project env vars — injected if present

PORTS
  Ports in CLODE_EXPOSE_PORTS are auto-forwarded at startup with dynamic
  host ports. Claude receives CLODE_PORT_<n>=<host_port> env vars so it
  knows the host-side URL. Run 'clode list' to see current mappings.
  Use -p to add extra ports beyond CLODE_EXPOSE_PORTS.

EXAMPLES
  clode                        Start or attach (smart default)
  clode start                  Explicitly start new session
  clode start --bg "fix tests"      Run task in background
  clode -p 9000:9000                Add an extra port this session
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
  local -a ports=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg)           bg=1;                    shift ;;
      --resume)       resume=1;                shift ;;
      --memory)       memory="$2";             shift 2 ;;
      --cpus)         cpus="$2";               shift 2 ;;
      -p|--port)      ports+=("-p" "$2");      shift 2 ;;
      *)              break ;;
    esac
  done

  if _clode_exists "$name"; then
    echo "clode: container '$name' already exists — use 'clode attach' or 'clode stop' first." >&2
    return 1
  fi

  local -a claude_flags=("--dangerously-skip-permissions")
  [[ $resume -eq 1 ]] && claude_flags+=("--resume")

  _clode_build_port_args
  local -a _args=()
  while IFS= read -r _line; do [[ -n "$_line" ]] && _args+=("$_line"); done \
    < <(_clode_base_args "$name" "$memory" "$cpus")
  # Combine: base args + auto port mappings + port env/labels + manual -p overrides
  local -a all_args=("${_args[@]}" "${_CLODE_PORT_ARGS[@]}" "${_CLODE_PORT_EXTRA[@]}" "${ports[@]}")

  if [[ $bg -eq 1 ]]; then
    docker run -d "${all_args[@]}" "$CLODE_IMAGE" "${claude_flags[@]}" "$@"
    echo "clode: started '$name' in background"
    for line in "${_CLODE_PORT_LINES[@]}"; do echo "$line"; done

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
    for line in "${_CLODE_PORT_LINES[@]}"; do echo "$line"; done
    docker run -it "${all_args[@]}" "$CLODE_IMAGE" "${claude_flags[@]}" "$@"
  fi
}

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
      # Show port mappings from labels (clode.port.<container>=<host>)
      while IFS='=' read -r key hport; do
        [[ "$key" == clode.port.* ]] || continue
        local cport="${key#clode.port.}"
        printf "  %-28s http://localhost:%-8s → container:%-s\n" "" "$hport" "$cport"
      done < <(docker inspect --format \
        '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' \
        "$cname" 2>/dev/null | grep '^clode\.port\.')
    else
      printf "%-30s %-20s %s\n" "$project" "-" "stopped"
    fi
  done
}

_clode_update() {
  _clode_load_config
  local reconfigure=0
  [[ "${1:-}" == "--reconfigure" ]] && reconfigure=1

  echo "clode: pulling latest image (${CLODE_IMAGE})..."
  docker pull "$CLODE_IMAGE"

  local script_dir
  local _clode_self
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    _clode_self="${(%):-%x}"
  else
    _clode_self="${BASH_SOURCE[0]}"
  fi
  script_dir="$(cd "$(dirname "$_clode_self")" && pwd)"

  if [[ $reconfigure -eq 1 ]]; then
    bash "${script_dir}/install.sh" --reconfigure
  else
    bash "${script_dir}/install.sh"
  fi

  echo "clode: updated. Run: source ~/.zshrc"
}

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

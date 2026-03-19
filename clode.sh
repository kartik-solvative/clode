# Claude Code in Docker — source this file from ~/.zshrc

# ── Config ────────────────────────────────────────────────
_CLODE_CONFIG="$HOME/.clode.config"
_CLODE_HOME="$HOME"
# Resolve the directory containing this script at source time
if [[ -n "${ZSH_VERSION:-}" ]]; then
  _CLODE_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  _CLODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

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
  # Add the claude group (GID 1001) as a supplementary group so the entrypoint
  # can write to /etc/passwd (owned by group claude with g+w).
  printf -- '--group-add\n1001\n'
  printf -- '-e\nHOME=%s\n' "$_CLODE_HOME"
  printf -- '-e\nCLAUDE_CODE_OAUTH_TOKEN=%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}"
  _clode_all_env_args
  printf -- '-v\n%s:%s\n' "$_CLODE_HOME/.claude" "$_CLODE_HOME/.claude"
  # .claude.json is NOT mounted — it contains user prefs that Claude Code writes
  # to during normal operation. Sharing it via bind mount between host and multiple
  # containers causes corruption from concurrent writes. The container gets auth via
  # CLAUDE_CODE_OAUTH_TOKEN and session data via ~/.claude/; it doesn't need this file.
  printf -- '-v\n%s:%s:ro\n' "$_CLODE_HOME/.ssh" "$_CLODE_HOME/.ssh"
  # Git identity and GitHub CLI auth
  [[ -f "$_CLODE_HOME/.gitconfig" ]] && \
    printf -- '-v\n%s:%s:ro\n' "$_CLODE_HOME/.gitconfig" "$_CLODE_HOME/.gitconfig"
  [[ -d "$_CLODE_HOME/.config/gh" ]] && \
    printf -- '-v\n%s:%s:ro\n' "$_CLODE_HOME/.config/gh" "$_CLODE_HOME/.config/gh"
  # Extract the active gh token from the host (where macOS Keychain is accessible)
  # and inject it as GH_TOKEN. Inside Docker there is no Keychain, so the mounted
  # ~/.config/gh credentials file alone is insufficient. GH_TOKEN env var takes
  # precedence over the credential store, so this works even with stale file tokens.
  local _gh_token
  _gh_token=$(gh auth token 2>/dev/null || true)
  [[ -n "$_gh_token" ]] && printf -- '-e\nGH_TOKEN=%s\n' "$_gh_token"
  # SSH agent forwarding — Docker Desktop for Mac exposes this socket
  if [[ -S "/run/host-services/ssh-auth.sock" ]]; then
    printf -- '-v\n/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock\n'
    printf -- '-e\nSSH_AUTH_SOCK=/run/host-services/ssh-auth.sock\n'
  fi
  # Rewrite GitHub push URLs to SSH so the forwarded SSH agent handles auth.
  # macOS credential helpers (gh, GCM) store tokens in the Keychain, which is
  # inaccessible inside Docker — SSH agent forwarding is the reliable alternative.
  # pushInsteadOf only affects push; fetch/clone continue to use HTTPS.
  printf -- '-e\nGIT_CONFIG_COUNT=1\n'
  printf -- '-e\nGIT_CONFIG_KEY_0=url.git@github.com:.pushInsteadOf\n'
  printf -- '-e\nGIT_CONFIG_VALUE_0=https://github.com/\n'
  # Ensure host.docker.internal resolves inside the container — Docker Desktop
  # provides this automatically, but Colima and other runtimes need the flag.
  printf -- '--add-host\nhost.docker.internal:host-gateway\n'
  # ~/.claude is already mounted above; just point the bridge at the Mac host
  # so PermissionRequest/Notification hooks reach Nod via host.docker.internal
  printf -- '-e\nNOD_HOST=host.docker.internal\n'
  # Bind address for dev servers — must be 0.0.0.0 inside Docker for port
  # mapping to work. Vite, CRA, and many Node servers read HOST automatically.
  printf -- '-e\nHOST=0.0.0.0\n'
  # Mac Chrome CDP endpoint — available when Chrome is started with chrome-debug
  printf -- '-e\nCHROME_CDP_URL=http://host.docker.internal:9222\n'
  # Shared clipboard directory: 'cpaste' on Mac writes here; Claude reads /tmp/clode-clipboard inside Docker
  mkdir -p "$HOME/.clode/clipboard" 2>/dev/null || true
  printf -- '-v\n%s:/tmp/clode-clipboard\n' "$HOME/.clode/clipboard"
  # Mount project at its actual host path (not /workspace) so Claude Code's
  # session history and memory are keyed by the same path on host and in Docker.
  # -w sets the working directory to match, making /resume find the right sessions.
  local _pwd
  _pwd="$(pwd)"
  printf -- '-v\n%s:%s\n' "$_pwd" "$_pwd"
  printf -- '-w\n%s\n' "$_pwd"
  # When running inside a git worktree, also mount the main repo's .git directory.
  # A worktree's .git file is a pointer to <main>/.git/worktrees/<name>, and the
  # object store / refs live in <main>/.git — without this mount, git is broken
  # inside the container (can't resolve the gitdir pointer).
  # Uses git rev-parse --git-common-dir to detect worktrees reliably (not path substring).
  local _git_common_dir _git_dir
  _git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || true
  _git_dir=$(git rev-parse --git-dir 2>/dev/null) || true
  if [[ -n "$_git_common_dir" && -n "$_git_dir" && "$_git_common_dir" != "$_git_dir" ]]; then
    # We're in a worktree; _git_common_dir is the main repo's .git
    # Resolve to absolute path
    _git_common_dir=$(cd "$_git_common_dir" && pwd)
    local _main_root="${_git_common_dir%/.git}"
    printf -- '-v\n%s:%s\n' "$_git_common_dir" "$_git_common_dir"
    # Mount .worktrees/ so Claude can create sibling worktrees from inside the
    # container. Without this, Docker creates it as a root-owned stub directory.
    if [[ -d "$_main_root/.worktrees" ]]; then
      printf -- '-v\n%s/.worktrees:%s/.worktrees\n' "$_main_root" "$_main_root"
    fi
  fi
  # Docker-environment instructions are injected via --append-system-prompt
  # on the claude command (see _clode_claude_flags), not via file mounting.
  printf -- '--name\n%s\n' "$name"
  printf -- '--label\nclode.workspace=%s\n' "$(pwd)"
  printf -- '--security-opt=no-new-privileges\n'
  printf -- '--cap-drop=ALL\n'
  printf -- '--memory=%s\n' "$memory"
  printf -- '--cpus=%s\n' "$cpus"
}

# Build the base claude CLI flags (--dangerously-skip-permissions + Docker context).
# Usage: local -a claude_flags=(); _clode_claude_flags claude_flags [--resume]
_clode_claude_flags() {
  # Populate a caller-provided array variable with the base claude CLI flags.
  # Uses eval instead of nameref (local -n) for zsh compatibility.
  local _varname="$1"
  local _resume="${2:-}"
  local -a _tmp=("--dangerously-skip-permissions")
  [[ "$_resume" == "--resume" ]] && _tmp+=("--resume")
  # Inject Docker-environment instructions directly into the system prompt.
  # This is more reliable than file mounting — works regardless of project
  # path, doesn't conflict with project CLAUDE.md, and is always active.
  if [[ -f "$_CLODE_DIR/CLAUDE.md" ]]; then
    _tmp+=("--append-system-prompt" "$(<"$_CLODE_DIR/CLAUDE.md")")
  fi
  eval "${_varname}=(\"\${_tmp[@]}\")"
}

# ── Helpers ───────────────────────────────────────────────
# Build a container name that's unique per worktree.
# Inside .worktrees/: "project--branch" to avoid cross-project collisions.
# Main worktree: plain project name.
_clode_name() {
  local dir
  dir="$(pwd)"
  if [[ "$dir" == */.worktrees/* ]]; then
    local project
    project=$(basename "${dir%%/.worktrees/*}")
    printf '%s--%s' "$project" "$(basename "$dir")"
  else
    basename "$dir"
  fi
}
_clode_is_running() { docker ps -q --filter "name=^${1}$" 2>/dev/null | grep -q .; }
_clode_exists()     { docker ps -aq --filter "name=^${1}$" 2>/dev/null | grep -q .; }

# Ask the OS for a free ephemeral port.
_clode_free_port() {
  python3 -c "import socket; s=socket.socket(); s.bind(('',0)); p=s.getsockname()[1]; s.close(); print(p)"
}

# List names of all RUNNING containers for the current directory (via clode.workspace label).
# Outputs one name per line.
_clode_running_for_path() {
  docker ps --filter "label=clode.workspace=$(pwd)" --format '{{.Names}}' 2>/dev/null
}

# Return the next available container name for the current directory.
#   _clode_next_name          -> <base>-2, <base>-3, … (never claims <base>)
#   _clode_next_name <label>  -> <base>--<sanitized-label> (errors if taken)
_clode_next_name() {
  local base
  base=$(_clode_name)

  if [[ $# -gt 0 && -n "$1" ]]; then
    # Labeled: sanitize then check availability.
    # Note: '-' is placed first in the negated class to avoid being parsed as a range.
    local label="$1"
    label="${label//\//-}"
    label="${label//[^-a-zA-Z0-9._]/-}"
    local name="${base}--${label}"
    if _clode_exists "$name"; then
      echo "clode: container '$name' already exists." >&2
      return 1
    fi
    echo "$name"
  else
    # Auto-numbered: start at <base>-2, never claim <base>
    local n=2
    local name="${base}-${n}"
    while _clode_exists "$name"; do
      n=$(( n + 1 ))
      name="${base}-${n}"
    done
    echo "$name"
  fi
}

# Show a numbered picker for a list of container names.
# Usage: _clode_pick_container name1 name2 …
# Echoes the chosen name to stdout. Returns 1 on failure.
# Uses ${CLODE_TTY:-/dev/tty} for input — set CLODE_TTY in tests only.
_clode_pick_container() {
  local names=("$@")
  local n=${#names[@]}
  local project
  project=$(basename "$(pwd)")
  local _tty="${CLODE_TTY:-/dev/tty}"

  # Build a name->status map from running containers
  local -A status_map
  while IFS=$'\t' read -r cname cstatus; do
    [[ -n "$cname" ]] && status_map["$cname"]="$cstatus"
  done < <(docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null)

  # Print menu to stderr
  echo "clode: multiple sessions for '${project}':" >&2
  local i
  for (( i=0; i<n; i++ )); do
    local cname="${names[$i]}"
    local cstatus="${status_map[$cname]:-stopped}"
    printf '  %d) %-30s (%s)\n' "$(( i+1 ))" "$cname" "$cstatus" >&2
  done

  # Check tty is available
  if ! true <"$_tty" 2>/dev/null; then
    echo "clode: multiple sessions running for '${project}' — cannot pick non-interactively." >&2
    echo "       Run from a terminal or stop containers manually." >&2
    return 1
  fi

  local attempt=0
  local choice
  while [[ $attempt -lt 3 ]]; do
    printf 'Attach to [1-%d]: ' "$n" >&2
    if ! IFS= read -r choice <"$_tty" 2>/dev/null; then
      echo "clode: failed to read from terminal." >&2
      return 1
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      echo "${names[$(( choice - 1 ))]}"
      return 0
    fi
    echo "clode: invalid selection '$choice' — enter a number between 1 and ${n}." >&2
    attempt=$(( attempt + 1 ))
  done

  echo "clode: too many invalid attempts." >&2
  return 1
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
  start [--bg] [prompt]       Explicitly start a new session
  new [label] [flags] [prompt]  Start an additional session in this directory
  attach                      Attach to running container (error if none)
  stop                        Stop and remove current project's container
  list [--all]                List running containers (--all includes stopped)
  worktree add <branch>       Create worktree + start Claude in it
  worktree remove             Stop container + remove current worktree
  worktree list               List all worktrees for this project
  update [--reconfigure]      Pull latest image, update shell config
  help                        Show this help message

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

BROWSER
  chrome-debug                 Start Mac Chrome with CDP on port 9222
                               Claude inside Docker connects via $CHROME_CDP_URL
                               (Headless Chromium is also available inside Docker)

CLIPBOARD
  cpaste                       Copy clipboard → /tmp/clode-clipboard/
                               Handles: files (Finder Cmd+C), images, text
                               Tip: brew install pngpaste (faster image paste)

EXAMPLES
  clode                        Start or attach (smart default)
  clode start                  Explicitly start new session
  clode new                    Start a second session (auto-named myproject-2)
  clode new fix-auth           Start a second session labeled 'fix-auth'
  clode new --bg "run tests"   Background session with no label
  clode start --bg "fix tests"      Run task in background
  clode -p 9000:9000                Add an extra port this session
  clode attach                 Attach to running session
  clode stop                   Stop current project's container
  clode list                   Show all projects and status
  clode update                 Pull latest image
  clode update --reconfigure   Update + change settings
EOF
}

_clode_new() {
  _clode_load_config

  # Extract optional label (first arg matching label pattern)
  local label=""
  if [[ $# -gt 0 && "${1:-}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]]; then
    label="$1"
    shift
  fi

  local bg=0 resume=0 memory="4g" cpus="2"
  local -a ports=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg)           bg=1;               shift ;;
      --resume)       resume=1;           shift ;;
      --memory)       memory="$2";        shift 2 ;;
      --cpus)         cpus="$2";          shift 2 ;;
      -p|--port)      ports+=("-p" "$2"); shift 2 ;;
      *)              break ;;
    esac
  done

  local name
  if ! name=$(_clode_next_name "$label"); then
    return 1
  fi

  local _resume_flag=""
  [[ $resume -eq 1 ]] && _resume_flag="--resume"
  local -a claude_flags
  _clode_claude_flags claude_flags "$_resume_flag"

  _clode_build_port_args
  local -a _args=()
  while IFS= read -r _line; do [[ -n "$_line" ]] && _args+=("$_line"); done \
    < <(_clode_base_args "$name" "$memory" "$cpus")
  local -a all_args=("${_args[@]}" "${_CLODE_PORT_ARGS[@]}" "${_CLODE_PORT_EXTRA[@]}" "${ports[@]}")

  if [[ $bg -eq 1 ]]; then
    docker run -d "${all_args[@]}" "$CLODE_IMAGE" "${claude_flags[@]}" "$@"
    echo "clode: started '$name' in background"
    for line in "${_CLODE_PORT_LINES[@]}"; do echo "$line"; done

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

  local _resume_flag=""
  [[ $resume -eq 1 ]] && _resume_flag="--resume"
  local -a claude_flags
  _clode_claude_flags claude_flags "$_resume_flag"

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
  local -a names=()
  while IFS= read -r _n; do [[ -n "$_n" ]] && names+=("$_n"); done \
    < <(_clode_running_for_path)

  local count=${#names[@]}

  if [[ $count -eq 0 ]]; then
    echo "clode: no running container for '$(pwd)'." >&2
    echo "       Run 'clode start' to begin a session." >&2
    return 1
  fi

  local name
  if [[ $count -eq 1 ]]; then
    name="${names[0]}"
  else
    if ! name=$(_clode_pick_container "${names[@]}"); then
      return 1
    fi
  fi

  echo "clode: attaching to '$name'"
  docker exec -it "$name" claude --dangerously-skip-permissions --resume
}

_clode_stop() {
  local -a names=()
  while IFS= read -r _n; do [[ -n "$_n" ]] && names+=("$_n"); done \
    < <(_clode_running_for_path)

  local count=${#names[@]}

  if [[ $count -eq 0 ]]; then
    echo "clode: no container found for '$(pwd)'." >&2
    return 1
  fi

  local name
  if [[ $count -eq 1 ]]; then
    name="${names[0]}"
  else
    if ! name=$(_clode_pick_container "${names[@]}"); then
      return 1
    fi
  fi

  docker stop "$name" >/dev/null && docker rm "$name" >/dev/null 2>&1 || true
  echo "clode: stopped '$name'"
}

_clode_list() {
  _clode_load_config
  local show_all=0
  [[ "${1:-}" == "--all" ]] && show_all=1

  # Running containers with clode.workspace label
  local found=0
  while IFS='|' read -r cname wspath; do
    [[ -n "$cname" ]] || continue
    found=1
    local project
    project=$(basename "$wspath")
    local ports=""
    while IFS='=' read -r key hport; do
      [[ "$key" == clode.port.* ]] || continue
      local cport="${key#clode.port.}"
      ports="${ports:+$ports  }:${hport}→${cport}"
    done < <(docker inspect --format \
      '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' \
      "$cname" 2>/dev/null | grep '^clode\.port\.')
    printf "%-25s running    %s\n" "$cname" "$ports"
  done < <(docker ps --filter "label=clode.workspace" \
    --format '{{.Names}}|{{.Label "clode.workspace"}}' 2>/dev/null)

  if [[ $found -eq 0 && $show_all -eq 0 ]]; then
    echo "No running clode containers. Use 'clode list --all' to see all projects."
    return 0
  fi

  # Stopped projects — only with --all
  if [[ $show_all -eq 1 && -d "$CLODE_WORKSPACE" ]]; then
    # Collect running workspace paths to skip them
    declare -A running_paths
    while IFS='|' read -r cname wspath; do
      [[ -n "$wspath" ]] && running_paths["$wspath"]=1
    done < <(docker ps --filter "label=clode.workspace" \
      --format '{{.Names}}|{{.Label "clode.workspace"}}' 2>/dev/null)

    for dir in "$CLODE_WORKSPACE"/*/; do
      [[ -d "$dir" ]] || continue
      local abspath
      abspath=$(cd "$dir" && pwd)
      [[ -n "${running_paths[$abspath]:-}" ]] && continue
      printf "%-25s stopped\n" "$(basename "$dir")"
    done
  fi
}

_clode_worktree() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    add)
      local branch="${1:-}"
      if [[ -z "$branch" ]]; then
        echo "Usage: clode worktree add <branch>" >&2
        return 1
      fi
      if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "clode: not a git repository" >&2
        return 1
      fi
      if [[ "$(pwd)" == */.worktrees/* ]]; then
        echo "clode: already inside a worktree — run from the main project directory" >&2
        return 1
      fi
      local slug="${branch//\//-}"
      local wt_path=".worktrees/$slug"
      mkdir -p .worktrees
      # Try new branch first, fall back to checking out existing branch
      if ! git worktree add "$wt_path" -b "$branch" 2>/dev/null; then
        git worktree add "$wt_path" "$branch" || return 1
      fi
      echo "clode: worktree ready at $wt_path"
      cd "$wt_path" || return 1
      _clode_start "$@"
      ;;
    remove)
      if [[ "$(pwd)" != */.worktrees/* ]]; then
        echo "clode: not inside a worktree" >&2
        return 1
      fi
      local wt_path
      wt_path="$(pwd)"
      local project_root="${wt_path%%/.worktrees/*}"
      _clode_stop 2>/dev/null || true
      cd "$project_root" || return 1
      git worktree remove "$wt_path" --force
      echo "clode: removed worktree $wt_path"
      ;;
    list)
      git worktree list 2>/dev/null || { echo "clode: not a git repository" >&2; return 1; }
      ;;
    *)
      echo "Usage: clode worktree add <branch>  — create worktree + start Claude" >&2
      echo "       clode worktree remove        — stop container + remove worktree" >&2
      echo "       clode worktree list          — list all worktrees" >&2
      return 1
      ;;
  esac
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
      shift
      _clode_list "$@"
      ;;
    worktree)
      shift
      _clode_worktree "$@"
      ;;
    update)
      shift
      _clode_update "${1:-}"
      ;;
    new)
      shift
      _clode_new "$@"
      ;;
    *)
      # Smart default: attach (with picker if 2+) if any running, else start new
      local -a _names=()
      while IFS= read -r _n; do [[ -n "$_n" ]] && _names+=("$_n"); done \
        < <(_clode_running_for_path)
      if [[ ${#_names[@]} -eq 0 ]]; then
        echo "clode: no running container — starting new session"
        _clode_start "$@"
      else
        echo "clode: container(s) running — attaching"
        _clode_attach
      fi
      ;;
  esac
}

# ── chrome-debug — start Mac Chrome with CDP for Docker access ────────────
# Usage: chrome-debug [extra Chrome flags]
# Claude inside Docker can connect via $CHROME_CDP_URL (http://host.docker.internal:9222)
chrome-debug() {
  local chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if [[ ! -x "$chrome" ]]; then
    echo "chrome-debug: Chrome not found at '$chrome'" >&2
    return 1
  fi
  if curl -s --connect-timeout 1 "http://localhost:9222/json/version" >/dev/null 2>&1; then
    echo "chrome-debug: Chrome CDP already listening on port 9222"
    echo "              Connect from Docker via: http://host.docker.internal:9222"
    return 0
  fi
  "$chrome" \
    --remote-debugging-port=9222 \
    --no-first-run \
    --no-default-browser-check \
    "$@" &
  disown
  echo "chrome-debug: Chrome started with CDP on port 9222"
  echo "              Connect from Docker via: \$CHROME_CDP_URL"
}

# ── cpaste — clipboard bridge (files, images, text) ───────
# Copies whatever is on the macOS clipboard into ~/.clode/clipboard/
# so Claude running inside Docker can read it at /tmp/clode-clipboard/
#
# Priority: file references (Finder Cmd+C) → image → text
cpaste() {
  local dir="$HOME/.clode/clipboard"
  mkdir -p "$dir"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # ── 1. File references (files copied in Finder) ──────────
  local filepaths
  filepaths=$(osascript 2>/dev/null <<'APPLESCRIPT'
    try
      set theClip to (the clipboard as «class furl»)
      if class of theClip is list then
        set out to ""
        repeat with f in theClip
          set out to out & POSIX path of f & linefeed
        end repeat
        return out
      else
        return POSIX path of theClip
      end if
    end try
    return ""
APPLESCRIPT
  )
  if [[ -n "$filepaths" ]]; then
    while IFS= read -r fp; do
      [[ -z "$fp" ]] && continue
      cp -r "$fp" "$dir/"
      echo "cpaste: /tmp/clode-clipboard/$(basename "$fp")"
    done <<< "$filepaths"
    return 0
  fi

  # ── 2. Image ──────────────────────────────────────────────
  local imgfile="$dir/clipboard_${timestamp}.png"
  if command -v pngpaste >/dev/null 2>&1; then
    if pngpaste "$imgfile" 2>/dev/null; then
      cp "$imgfile" "$dir/clipboard.png"
      echo "cpaste: /tmp/clode-clipboard/clipboard_${timestamp}.png"
      echo "        (also: /tmp/clode-clipboard/clipboard.png)"
      return 0
    fi
  elif osascript 2>/dev/null <<APPLESCRIPT
    set imgData to (the clipboard as «class PNGf»)
    set f to open for access POSIX file "$imgfile" with write permission
    write imgData to f
    close access f
APPLESCRIPT
  then
    cp "$imgfile" "$dir/clipboard.png"
    echo "cpaste: /tmp/clode-clipboard/clipboard_${timestamp}.png"
    echo "        (also: /tmp/clode-clipboard/clipboard.png)"
    return 0
  fi

  # ── 3. Text ───────────────────────────────────────────────
  local text
  text=$(pbpaste 2>/dev/null)
  if [[ -n "$text" ]]; then
    local txtfile="$dir/clipboard_${timestamp}.txt"
    printf '%s' "$text" > "$txtfile"
    cp "$txtfile" "$dir/clipboard.txt"
    echo "cpaste: /tmp/clode-clipboard/clipboard_${timestamp}.txt"
    echo "        (also: /tmp/clode-clipboard/clipboard.txt)"
    return 0
  fi

  echo "cpaste: clipboard is empty or type not supported" >&2
  return 1
}

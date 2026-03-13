# Claude Code in Docker — source this file from ~/.zshrc
_CLODE_HOME="$HOME"
_CLODE_IMAGE="claude-code:latest"

_clode_base_args() {
  local name=$(basename $(pwd))
  echo "--rm \
    -u $(id -u):$(id -g) \
    -e HOME=${_CLODE_HOME} \
    -e CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN} \
    -v ${_CLODE_HOME}/.claude:${_CLODE_HOME}/.claude \
    -v ${_CLODE_HOME}/.claude.json:${_CLODE_HOME}/.claude.json \
    -v ${_CLODE_HOME}/.ssh:${_CLODE_HOME}/.ssh:ro \
    -v $(pwd):/workspace \
    --name ${name} \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --memory=4g \
    --cpus=2"
}

_clode_help() {
  cat <<'EOF'
clode — Claude Code in Docker

USAGE
  clode [flags] [prompt]
  clode <subcommand> [args]

SUBCOMMANDS
  attach          Attach to the running session for the current directory
  stop            Stop and remove the container for the current directory
  list            List all running clode containers
  logs [--follow] Show logs for the current directory's container
  help            Show this help message

FLAGS (for the default "run" mode)
  --resume        Resume the last conversation
  --bg            Run detached in the background (non-interactive)
  --memory <mem>  Override container memory limit (default: 4g)
  --cpus <n>      Override container CPU limit (default: 2)
  -h, --help      Show this help message

EXAMPLES
  clode                        Start interactive session
  clode --resume               Resume last conversation
  clode --bg "fix the tests"   Run a task in the background
  clode attach                 Re-attach to a running session
  clode stop                   Stop the current directory's container
  clode list                   List all running containers
  clode logs                   Tail logs for the current container
  clode logs --follow          Follow logs live

ENVIRONMENT
  CLAUDE_CODE_OAUTH_TOKEN      Required — your Claude OAuth token
  NTFY_TOPIC                   Optional — ntfy.sh topic for bg completion alerts
EOF
}

clode() {
  local name=$(basename $(pwd))
  local resume=0
  local bg=0
  local memory="4g"
  local cpus="2"

  # Parse flags and subcommands
  case "${1}" in
    -h|--help|help)
      _clode_help
      return 0
      ;;
    attach)
      docker exec -it "$name" claude --dangerously-skip-permissions --resume
      return $?
      ;;
    stop)
      docker stop "$name" && docker rm "$name"
      return $?
      ;;
    list)
      docker ps --filter "ancestor=${_CLODE_IMAGE}" \
        --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"
      return $?
      ;;
    logs)
      shift
      if [[ "${1}" == "--follow" || "${1}" == "-f" ]]; then
        docker logs -f "$name"
      else
        docker logs "$name"
      fi
      return $?
      ;;
  esac

  # Flag parsing for run mode
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume)    resume=1;      shift ;;
      --bg)        bg=1;          shift ;;
      --memory)    memory="$2";   shift 2 ;;
      --cpus)      cpus="$2";     shift 2 ;;
      -h|--help)   _clode_help;   return 0 ;;
      *)           break ;;
    esac
  done

  local base_args="--rm \
    -u $(id -u):$(id -g) \
    -e HOME=${_CLODE_HOME} \
    -e CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN} \
    -v ${_CLODE_HOME}/.claude:${_CLODE_HOME}/.claude \
    -v ${_CLODE_HOME}/.claude.json:${_CLODE_HOME}/.claude.json \
    -v ${_CLODE_HOME}/.ssh:${_CLODE_HOME}/.ssh:ro \
    -v $(pwd):/workspace \
    --name ${name} \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --memory=${memory} \
    --cpus=${cpus}"

  local claude_flags="--dangerously-skip-permissions"
  [[ $resume -eq 1 ]] && claude_flags="${claude_flags} --resume"

  docker rm "$name" 2>/dev/null || true

  if [[ $bg -eq 1 ]]; then
    eval docker run -d ${base_args} ${_CLODE_IMAGE} ${claude_flags} "$@"
    echo "Started: $name"
    if [[ -n "${NTFY_TOPIC}" ]]; then
      (docker wait "$name" >/dev/null 2>&1 && \
        curl -s -o /dev/null "https://ntfy.sh/${NTFY_TOPIC}" \
          -H "Title: clode done" \
          -H "Tags: white_check_mark" \
          -d "$name finished") &
    fi
  else
    eval docker run -it ${base_args} ${_CLODE_IMAGE} ${claude_flags} "$@"
  fi
}

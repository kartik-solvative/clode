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

clode()        { eval docker run -it $(_clode_base_args) ${_CLODE_IMAGE} --dangerously-skip-permissions "$@"; }
clode-resume() { eval docker run -it $(_clode_base_args) ${_CLODE_IMAGE} --dangerously-skip-permissions --resume "$@"; }
clode-bg() {
  local name=$(basename $(pwd))
  docker rm "$name" 2>/dev/null || true
  eval docker run -d \
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
    --cpus=2 \
    ${_CLODE_IMAGE} --dangerously-skip-permissions "$@"
  echo "Started: $name"
}
clode-attach() { docker exec -it $(basename $(pwd)) claude --dangerously-skip-permissions --resume; }
clode-stop()   { docker stop $(basename $(pwd)) && docker rm $(basename $(pwd)); }
clode-list()   { docker ps --filter "ancestor=${_CLODE_IMAGE}" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"; }
clode-logs()   { docker logs $(basename $(pwd)); }

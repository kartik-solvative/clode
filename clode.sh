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
      printf -- '-e %q\n' "$line"
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

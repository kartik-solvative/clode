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

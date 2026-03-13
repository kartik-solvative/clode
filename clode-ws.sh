# clode-ws — tmux workspace manager for Claude Code
# Source from ~/.zshrc: source "$HOME/Projects/clode/clode-ws.sh"

_CLODE_WS_HOME="$HOME"
_CLODE_WS_IMAGE="claude-code:latest"
_CLODE_WS_PROJECTS_DIR="$HOME/Projects"

# Sanitise a branch name or worktree path to a window-safe slug.
# - strips leading .worktrees/
# - replaces / and whitespace with -
_cws_slugify() {
  local input="$1"
  input="${input#.worktrees/}"
  echo "${input//[\/[:space:]]/-}"
}

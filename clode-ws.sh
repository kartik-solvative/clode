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

_cws_session_name() {
  echo "cws-${1}"
}

_cws_container_name() {
  local project="$1" slug="$2"
  echo "cws-${project}-${slug}"
}

_cws_window_name() {
  local slug="$1" type="$2" n="$3"
  echo "${slug}:${type}-${n}"
}

# Resolve a worktree slug back to its filesystem path.
# "main" → ~/Projects/<project>/
# anything else → ~/Projects/<project>/.worktrees/<slug>/
_cws_worktree_dir() {
  local project="$1" slug="$2"
  if [[ "$slug" == "main" ]]; then
    echo "${_CLODE_WS_PROJECTS_DIR}/${project}"
  else
    echo "${_CLODE_WS_PROJECTS_DIR}/${project}/.worktrees/${slug}"
  fi
}

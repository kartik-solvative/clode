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

# List all active cws-* session names.
_cws_sessions() {
  tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^cws-" || true
}

# Check if a cws session exists for a project.
_cws_session_exists() {
  local session
  session=$(_cws_session_name "$1")
  tmux has-session -t "$session" 2>/dev/null
}

# List windows in a session, optionally filtered to a worktree slug.
# Output: one window name per line.
_cws_windows() {
  local session="$1" slug="${2:-}"
  local names
  names=$(tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null) || return 0
  if [[ -n "$slug" ]]; then
    echo "$names" | grep "^${slug}:" || true
  else
    echo "$names"
  fi
}

# Return the next available index for a terminal type in a worktree.
# e.g. if main:host-1 and main:host-2 exist, returns 3.
_cws_next_n() {
  local session="$1" slug="$2" type="$3"
  local max=0
  local pattern="${slug}:${type}-"
  while IFS= read -r name; do
    if [[ "$name" == ${pattern}* ]]; then
      local n="${name#${pattern}}"
      [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )) && max=$n
    fi
  done < <(_cws_windows "$session")
  echo $(( max + 1 ))
}

# Navigate to a session+window from inside or outside tmux.
# Window names contain ":" (e.g. main:host-1), so we use "=<name>" for exact
# match to prevent tmux parsing the colon as a pane separator.
_cws_goto() {
  local session="$1" window="${2:-}"
  if [[ -n "$window" ]]; then
    tmux select-window -t "${session}:=${window}" 2>/dev/null || true
  fi
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$session"
  else
    tmux attach-session -t "$session"
  fi
}

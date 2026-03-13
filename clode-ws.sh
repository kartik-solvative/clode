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

# List all git repo names under the projects directory, alphabetically.
_cws_projects() {
  for dir in "${_CLODE_WS_PROJECTS_DIR}"/*/; do
    [[ -d "${dir}.git" ]] || continue
    basename "$dir"
  done | sort
}

# List worktree slugs for a project. "main" is always printed first,
# then remaining worktrees in git-reported order.
_cws_worktrees() {
  local project="$1"
  local project_dir="${_CLODE_WS_PROJECTS_DIR}/${project}"
  local project_dir_real
  # Resolve symlinks in the project directory path
  project_dir_real=$(realpath "$project_dir" 2>/dev/null) || project_dir_real="$project_dir"

  # Always emit main first — do not rely on git's output order
  echo "main"

  git -C "$project_dir" worktree list --porcelain 2>/dev/null \
    | grep "^worktree " \
    | awk '{print $2}' \
    | while IFS= read -r path; do
        # Skip the main worktree — already printed above
        [[ "$path" == "$project_dir_real" ]] && continue
        # Extract relative path from project root
        local rel="${path#${project_dir_real}/}"
        _cws_slugify "$rel"
      done
}

# List active clode-ws sessions and their windows.
_cws_cmd_list() {
  local sessions
  sessions=$(_cws_sessions)
  if [[ -z "$sessions" ]]; then
    echo "No active clode-ws sessions."
    return 0
  fi
  echo "Active clode-ws sessions:"
  while IFS= read -r session; do
    local project="${session#cws-}"
    local windows
    windows=$(tmux list-windows -t "$session" -F "  #{window_index}: #{window_name}" 2>/dev/null)
    echo "● $project"
    echo "$windows"
  done <<< "$sessions"
}

# Create a new clode-ws session for a project with interactive worktree/terminal picker.
_cws_cmd_new() {
  local project="$1"
  if [[ -z "$project" ]]; then
    echo "Usage: clode-ws new <project>" >&2
    return 1
  fi

  local project_dir="${_CLODE_WS_PROJECTS_DIR}/${project}"
  if [[ ! -d "$project_dir" ]]; then
    echo "Error: $project_dir does not exist." >&2
    return 1
  fi
  if [[ ! -d "${project_dir}/.git" ]]; then
    echo "Error: $project_dir is not a git repository." >&2
    return 1
  fi

  local session
  session=$(_cws_session_name "$project")

  if _cws_session_exists "$project"; then
    echo "Session $session already exists — attaching."
  else
    tmux new-session -d -s "$session" -c "$project_dir"
    # Rename the default window to main:host-1
    tmux rename-window -t "${session}:1" "main:host-1"
    echo "Created session: $session"
  fi

  # Open navigator: worktree picker → terminal picker
  local slug
  slug=$(_cws_navigate_worktree "$project") || return 0
  [[ -z "$slug" ]] && return 0
  _cws_navigate_terminal "$project" "$slug"
}

# Kill a clode-ws session and all its containers.
_cws_cmd_kill() {
  local force=0
  if [[ "$1" == "--force" ]]; then
    force=1
    shift
  fi

  local project="$1"
  if [[ -z "$project" ]]; then
    echo "Usage: clode-ws kill [--force] <project>" >&2
    return 1
  fi

  local session
  session=$(_cws_session_name "$project")

  if [[ $force -eq 0 ]]; then
    printf "Kill session %s and all its containers? [y/N] " "$session"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0
  fi

  # Stop and remove all cws containers for this project
  # docker --filter name= is substring match — post-filter with grep to get only this project's containers
  local containers
  containers=$(docker ps -a --filter "name=cws-${project}-" --format "{{.Names}}" 2>/dev/null \
    | grep "^cws-${project}-")
  if [[ -n "$containers" ]]; then
    echo "Removing containers: $containers"
    echo "$containers" | xargs docker rm -f 2>/dev/null || true
  fi

  # Kill tmux session
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
    echo "Killed session: $session"
  else
    echo "Warning: session $session not found (containers cleaned up anyway)."
  fi
}

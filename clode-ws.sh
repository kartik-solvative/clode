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

# Remove all non-running clode-ws containers (exited, created, paused, dead).
_cws_cmd_prune() {
  local containers
  # All non-running cws-* containers (exited, created, paused, or dead)
  # Multiple docker ps calls because Docker ANDs multiple --filter status= values
  containers=$(
    { docker ps -a --filter "name=cws-" --filter "status=exited"  --format "{{.Names}}" 2>/dev/null
      docker ps -a --filter "name=cws-" --filter "status=created" --format "{{.Names}}" 2>/dev/null
      docker ps -a --filter "name=cws-" --filter "status=paused"  --format "{{.Names}}" 2>/dev/null
      docker ps -a --filter "name=cws-" --filter "status=dead"    --format "{{.Names}}" 2>/dev/null
    } | grep "^cws-" | sort -u
  )

  if [[ -z "$containers" ]]; then
    echo "Nothing to prune."
    return 0
  fi

  echo "Removing non-running containers:"
  echo "$containers"
  echo "$containers" | xargs docker rm 2>/dev/null || true
  echo "Done."
}

_cws_new_host_terminal() {
  local project="$1" slug="$2"
  local session
  session=$(_cws_session_name "$project")
  local n
  n=$(_cws_next_n "$session" "$slug" "host")
  local wname
  wname=$(_cws_window_name "$slug" "host" "$n")
  local worktree_dir
  worktree_dir=$(_cws_worktree_dir "$project" "$slug")

  tmux new-window -t "$session" -n "$wname" -c "$worktree_dir"
  _cws_goto "$session" "$wname"
}

_cws_new_clode_terminal() {
  local project="$1" slug="$2"
  local session
  session=$(_cws_session_name "$project")
  local worktree_dir
  worktree_dir=$(_cws_worktree_dir "$project" "$slug")
  local container
  container=$(_cws_container_name "$project" "$slug")

  # Guard: if container is already running, tell the user to use fg instead
  if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
    echo "Container ${container} is already running." >&2
    echo "Use 'fg' in the navigator to reattach to the existing conversation." >&2
    return 1
  fi

  # Remove stale (stopped) container if present
  if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
    echo "Warning: removing stale container ${container}" >&2
    docker rm -f "$container" 2>/dev/null || true
  fi

  local n
  n=$(_cws_next_n "$session" "$slug" "clode")
  local wname
  wname=$(_cws_window_name "$slug" "clode" "$n")

  # Open a new tmux window that runs docker run -it directly (no -d + attach pattern)
  # No --rm so fg reattach works after closing the window
  tmux new-window -t "$session" -n "$wname" -c "$worktree_dir" \
    -- docker run -it \
      -u "$(id -u):$(id -g)" \
      -e "HOME=${_CLODE_WS_HOME}" \
      -e "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}" \
      -v "${_CLODE_WS_HOME}/.claude:${_CLODE_WS_HOME}/.claude" \
      -v "${_CLODE_WS_HOME}/.claude.json:${_CLODE_WS_HOME}/.claude.json" \
      -v "${_CLODE_WS_HOME}/.ssh:${_CLODE_WS_HOME}/.ssh:ro" \
      -v "${worktree_dir}:/workspace" \
      --name "${container}" \
      --security-opt=no-new-privileges \
      --cap-drop=ALL \
      --memory=4g \
      --cpus=2 \
      "${_CLODE_WS_IMAGE}" --dangerously-skip-permissions

  # ntfy notification on container exit (background watcher)
  if [[ -n "${NTFY_TOPIC}" ]]; then
    (docker wait "$container" >/dev/null 2>&1 && \
      curl -s -o /dev/null "https://ntfy.sh/${NTFY_TOPIC}" \
        -H "Title: clode done" \
        -H "Tags: white_check_mark" \
        -d "${project}/${slug} finished") &
  fi

  _cws_goto "$session" "$wname"
}

_cws_fg_clode() {
  local project="$1" slug="$2"
  local session
  session=$(_cws_session_name "$project")
  local container
  container=$(_cws_container_name "$project" "$slug")

  # Check container is actually running (exact name match — docker filter is substring-only)
  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
    echo "Container ${container} not found — it may have exited. Use 'new clode terminal' to start fresh."
    return 1
  fi

  local n
  n=$(_cws_next_n "$session" "$slug" "clode")
  local wname
  wname=$(_cws_window_name "$slug" "clode" "$n")
  local worktree_dir
  worktree_dir=$(_cws_worktree_dir "$project" "$slug")

  # Open a new window that execs into the running container
  tmux new-window -t "$session" -n "$wname" -c "$worktree_dir" \
    -- docker exec -it "$container" claude --dangerously-skip-permissions --resume

  _cws_goto "$session" "$wname"
}

_cws_add_worktree() {
  local project="$1"
  local project_dir="${_CLODE_WS_PROJECTS_DIR}/${project}"

  printf "Branch name for new worktree: "
  read -r branch
  [[ -z "$branch" ]] && return 0

  local slug
  slug=$(_cws_slugify "$branch")
  local worktree_path="${project_dir}/.worktrees/${slug}"

  if [[ -d "$worktree_path" ]]; then
    echo "Worktree already exists: $worktree_path" >&2
    return 1
  fi

  mkdir -p "${project_dir}/.worktrees"
  if ! git -C "$project_dir" worktree add "$worktree_path" -b "$branch" 2>&1; then
    echo "git worktree add failed — see error above." >&2
    return 1
  fi

  echo "Created worktree: $worktree_path (branch: $branch)"
}

_cws_delete_worktree() {
  local project="$1" slug="$2"
  local session
  session=$(_cws_session_name "$project")
  local project_dir="${_CLODE_WS_PROJECTS_DIR}/${project}"
  local worktree_path="${project_dir}/.worktrees/${slug}"

  printf "Delete worktree '%s' and all its terminals/containers? [y/N] " "$slug"
  read -r confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || return 0

  # 1. Switch active client away from any window in this worktree before killing
  if [[ -n "$TMUX" ]]; then
    local current_window
    current_window=$(tmux display-message -p "#{window_name}" 2>/dev/null)
    if [[ "$current_window" == ${slug}:* ]]; then
      # "=" prefix = exact window name match (avoids colon being parsed as pane separator)
      tmux select-window -t "${session}:=main:host-1" 2>/dev/null || \
        tmux select-window -t "${session}:^" 2>/dev/null || true
    fi
  fi

  # 2. Kill tmux windows for this worktree
  # "=" prefix = exact window name match (avoids colon being parsed as pane separator)
  _cws_windows "$session" "$slug" | while IFS= read -r wname; do
    tmux kill-window -t "${session}:=${wname}" 2>/dev/null || true
  done

  # 3. Stop and remove clode containers for this worktree
  local container
  container=$(_cws_container_name "$project" "$slug")
  docker rm -f "$container" 2>/dev/null || true

  # 4. Remove the git worktree
  if [[ -d "$worktree_path" ]]; then
    git -C "$project_dir" worktree remove "$worktree_path" --force 2>&1 || true
    echo "Removed worktree: $worktree_path"
  else
    echo "Worktree directory not found: $worktree_path"
  fi
}

_cws_navigate_project() {
  # Build merged list: active sessions first (●), then inactive git repos (○)
  local active_projects=()
  while IFS= read -r session; do
    active_projects+=("${session#cws-}")
  done < <(_cws_sessions)

  local lines=()

  # Active sessions first
  for p in "${active_projects[@]}"; do
    lines+=("● $p")
  done

  # All git repos not already listed
  while IFS= read -r project; do
    local already=0
    for ap in "${active_projects[@]}"; do
      [[ "$ap" == "$project" ]] && already=1 && break
    done
    [[ $already -eq 0 ]] && lines+=("○ $project")
  done < <(_cws_projects)

  # tmux-only sessions (session exists but no ~/Projects/<project>/)
  for p in "${active_projects[@]}"; do
    if [[ ! -d "${_CLODE_WS_PROJECTS_DIR}/${p}" ]]; then
      # Replace the ● entry with a [tmux only] label
      for i in "${!lines[@]}"; do
        [[ "${lines[$i]}" == "● $p" ]] && lines[$i]="● $p [tmux only]"
      done
    fi
  done

  if [[ ${#lines[@]} -eq 0 ]]; then
    echo "No projects found in ${_CLODE_WS_PROJECTS_DIR}" >&2
    return 1
  fi

  local choice
  choice=$(printf '%s\n' "${lines[@]}" | fzf \
    --height=50% --border \
    --prompt="project > " \
    --header="clode-ws — select project") || return 0

  [[ -z "$choice" ]] && return 0

  # Strip the ● / ○ prefix and any [tmux only] label
  local project="${choice#● }"
  project="${project#○ }"
  project="${project% \[tmux only\]}"

  echo "$project"
}

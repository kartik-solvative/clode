#!/usr/bin/env bats

# Load the functions under test (source-only, no side effects)
setup() {
  # Source only the helper functions, not the main entry point
  source "$BATS_TEST_DIRNAME/../clode-ws.sh" 2>/dev/null || true
}

@test "_cws_slugify: strips .worktrees/ prefix" {
  result="$(_cws_slugify ".worktrees/feature-auth")"
  [ "$result" = "feature-auth" ]
}

@test "_cws_slugify: replaces / with -" {
  result="$(_cws_slugify "feature/auth")"
  [ "$result" = "feature-auth" ]
}

@test "_cws_slugify: replaces whitespace with -" {
  result="$(_cws_slugify "my feature")"
  [ "$result" = "my-feature" ]
}

@test "_cws_slugify: main passes through unchanged" {
  result="$(_cws_slugify "main")"
  [ "$result" = "main" ]
}

@test "_cws_slugify: nested path in .worktrees/" {
  result="$(_cws_slugify ".worktrees/fix/issue-42")"
  [ "$result" = "fix-issue-42" ]
}

@test "_cws_session_name: prefixes with cws-" {
  [ "$(_cws_session_name "focusreader")" = "cws-focusreader" ]
}

@test "_cws_container_name: cws-project-slug format" {
  [ "$(_cws_container_name "focusreader" "main")" = "cws-focusreader-main" ]
}

@test "_cws_container_name: handles feature slug" {
  [ "$(_cws_container_name "focusreader" "feature-auth")" = "cws-focusreader-feature-auth" ]
}

@test "_cws_window_name: worktree:type-n format" {
  [ "$(_cws_window_name "main" "host" "1")" = "main:host-1" ]
}

@test "_cws_window_name: clode type" {
  [ "$(_cws_window_name "feature-auth" "clode" "2")" = "feature-auth:clode-2" ]
}

@test "_cws_worktree_dir: main maps to project root" {
  result="$(_cws_worktree_dir "focusreader" "main")"
  [ "$result" = "$HOME/Projects/focusreader" ]
}

@test "_cws_worktree_dir: slug maps to .worktrees subdir" {
  result="$(_cws_worktree_dir "focusreader" "feature-auth")"
  [ "$result" = "$HOME/Projects/focusreader/.worktrees/feature-auth" ]
}

@test "_cws_next_n: returns 1 when no windows exist" {
  _cws_windows() { echo ""; }
  result="$(_cws_next_n "cws-test" "main" "host")"
  [ "$result" = "1" ]
}

@test "_cws_next_n: returns next index after existing windows" {
  _cws_windows() { printf "main:host-1\nmain:host-2\n"; }
  result="$(_cws_next_n "cws-test" "main" "host")"
  [ "$result" = "3" ]
}

@test "_cws_next_n: only counts matching type, not other types" {
  _cws_windows() { printf "main:host-1\nmain:clode-1\nmain:clode-2\n"; }
  result="$(_cws_next_n "cws-test" "main" "host")"
  [ "$result" = "2" ]
}

@test "_cws_projects: only lists git repos" {
  # Create a temp dir with one git repo and one plain dir
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/myrepo/.git" "$tmpdir/notgit"

  # Override the projects dir for this test
  _CLODE_WS_PROJECTS_DIR="$tmpdir"
  result="$(_cws_projects)"

  [ "$result" = "myrepo" ]
  rm -rf "$tmpdir"
}

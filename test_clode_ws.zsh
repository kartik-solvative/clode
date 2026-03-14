#!/usr/bin/env zsh
set -euo pipefail
PASS=0; FAIL=0

check() {
  local desc="$1" result="$2" expected="$3"
  if [[ "$result" == "$expected" ]]; then
    echo "  PASS: $desc"
    (( PASS++ )) || true
  else
    echo "  FAIL: $desc — got '$result', want '$expected'"
    (( FAIL++ )) || true
  fi
}

# Source the shell file
source /Users/kartiksorathiya/Projects/clode/.worktrees/cws-tui/clode-ws.sh

# Test: fzf nav functions are gone
check "no _cws_navigate_project" "$(type _cws_navigate_project 2>&1 | head -1 || true)" "_cws_navigate_project not found"
check "no _cws_navigate_worktree" "$(type _cws_navigate_worktree 2>&1 | head -1 || true)" "_cws_navigate_worktree not found"
check "no _cws_navigate_terminal" "$(type _cws_navigate_terminal 2>&1 | head -1 || true)" "_cws_navigate_terminal not found"

# Test: helper functions still defined
# Note: on macOS zsh, type outputs "foo is a shell function from /path" — match prefix only
check "_cws_new_host_terminal defined" "$(type _cws_new_host_terminal 2>&1 | head -1 | cut -d' ' -f1-5)" "_cws_new_host_terminal is a shell function"
check "_cws_new_clode_terminal defined" "$(type _cws_new_clode_terminal 2>&1 | head -1 | cut -d' ' -f1-5)" "_cws_new_clode_terminal is a shell function"
check "_cws_fg_clode defined" "$(type _cws_fg_clode 2>&1 | head -1 | cut -d' ' -f1-5)" "_cws_fg_clode is a shell function"
check "_cws_add_worktree defined" "$(type _cws_add_worktree 2>&1 | head -1 | cut -d' ' -f1-5)" "_cws_add_worktree is a shell function"
check "_cws_delete_worktree defined" "$(type _cws_delete_worktree 2>&1 | head -1 | cut -d' ' -f1-5)" "_cws_delete_worktree is a shell function"

# Test: cws is a function, not alias
check "cws is a function" "$(type cws 2>&1 | head -1 | cut -d' ' -f1-5)" "cws is a shell function"

# Test: clode-ws is a function
check "clode-ws is a function" "$(type clode-ws 2>&1 | head -1 | cut -d' ' -f1-5)" "clode-ws is a shell function"

echo ""
echo "Results: $PASS passed, $FAIL failed"
(( FAIL == 0 ))

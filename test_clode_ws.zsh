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

# Test: fzf nav functions are gone — use exit code (portable across zsh versions)
type _cws_navigate_project &>/dev/null && { echo "  FAIL: _cws_navigate_project still defined"; (( FAIL++ )) || true; } || { echo "  PASS: no _cws_navigate_project"; (( PASS++ )) || true; }
type _cws_navigate_worktree &>/dev/null && { echo "  FAIL: _cws_navigate_worktree still defined"; (( FAIL++ )) || true; } || { echo "  PASS: no _cws_navigate_worktree"; (( PASS++ )) || true; }
type _cws_navigate_terminal &>/dev/null && { echo "  FAIL: _cws_navigate_terminal still defined"; (( FAIL++ )) || true; } || { echo "  PASS: no _cws_navigate_terminal"; (( PASS++ )) || true; }

# Test: helper functions still defined
type _cws_new_host_terminal &>/dev/null && { echo "  PASS: _cws_new_host_terminal defined"; (( PASS++ )) || true; } || { echo "  FAIL: _cws_new_host_terminal not defined"; (( FAIL++ )) || true; }
type _cws_new_clode_terminal &>/dev/null && { echo "  PASS: _cws_new_clode_terminal defined"; (( PASS++ )) || true; } || { echo "  FAIL: _cws_new_clode_terminal not defined"; (( FAIL++ )) || true; }
type _cws_fg_clode &>/dev/null && { echo "  PASS: _cws_fg_clode defined"; (( PASS++ )) || true; } || { echo "  FAIL: _cws_fg_clode not defined"; (( FAIL++ )) || true; }
type _cws_add_worktree &>/dev/null && { echo "  PASS: _cws_add_worktree defined"; (( PASS++ )) || true; } || { echo "  FAIL: _cws_add_worktree not defined"; (( FAIL++ )) || true; }
type _cws_delete_worktree &>/dev/null && { echo "  PASS: _cws_delete_worktree defined"; (( PASS++ )) || true; } || { echo "  FAIL: _cws_delete_worktree not defined"; (( FAIL++ )) || true; }
type cws &>/dev/null && { echo "  PASS: cws defined"; (( PASS++ )) || true; } || { echo "  FAIL: cws not defined"; (( FAIL++ )) || true; }
type clode-ws &>/dev/null && { echo "  PASS: clode-ws defined"; (( PASS++ )) || true; } || { echo "  FAIL: clode-ws not defined"; (( FAIL++ )) || true; }

echo ""
echo "Results: $PASS passed, $FAIL failed"
(( FAIL == 0 ))

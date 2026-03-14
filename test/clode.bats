#!/usr/bin/env bats

setup() {
  # Source the file. No || true — if sourcing fails, tests should fail.
  source "$BATS_TEST_DIRNAME/../clode.sh" 2>/dev/null
}

# ── _clode_running_for_path ───────────────────────────────

@test "_clode_running_for_path: calls docker ps with correct label filter" {
  # The stub verifies that args include the label filter for the current path.
  docker() {
    local args="$*"
    [[ "$args" == *"label=clode.workspace=$(pwd)"* ]] || {
      echo "wrong docker args: $args" >&2; return 1
    }
    echo "myproject"
    echo "myproject-2"
  }
  result="$(_clode_running_for_path)"
  [ "$result" = "$(printf 'myproject\nmyproject-2')" ]
}

@test "_clode_running_for_path: returns empty when no containers" {
  docker() {
    [[ "$*" == *"label=clode.workspace=$(pwd)"* ]] || return 1
    return 0
  }
  result="$(_clode_running_for_path)"
  [ -z "$result" ]
}

# ── _clode_next_name ──────────────────────────────────────

@test "_clode_next_name: no label, nothing exists -> base-2" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  result="$(_clode_next_name)"
  [ "$result" = "myproject-2" ]
}

@test "_clode_next_name: no label, base-2 taken -> base-3" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { [[ "$1" == "myproject-2" ]]; }
  result="$(_clode_next_name)"
  [ "$result" = "myproject-3" ]
}

@test "_clode_next_name: no label, base-2 and base-3 taken -> base-4" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { [[ "$1" == "myproject-2" || "$1" == "myproject-3" ]]; }
  result="$(_clode_next_name)"
  [ "$result" = "myproject-4" ]
}

@test "_clode_next_name: with label, name free -> base--label" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  result="$(_clode_next_name "fix-auth")"
  [ "$result" = "myproject--fix-auth" ]
}

@test "_clode_next_name: label with slash sanitized to dash" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  result="$(_clode_next_name "fix/auth")"
  [ "$result" = "myproject--fix-auth" ]
}

@test "_clode_next_name: label preserves dot" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  result="$(_clode_next_name "feat.login")"
  [ "$result" = "myproject--feat.login" ]
}

@test "_clode_next_name: label with @ sanitized to dash" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  result="$(_clode_next_name "feat@v2")"
  [ "$result" = "myproject--feat-v2" ]
}

@test "_clode_next_name: empty string label falls through to auto-number" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  result="$(_clode_next_name "")"
  [ "$result" = "myproject-2" ]
}

@test "_clode_next_name: labeled name already exists -> non-zero exit" {
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 0; }
  run _clode_next_name "fix-auth"
  [ "$status" -ne 0 ]
}

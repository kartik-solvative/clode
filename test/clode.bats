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
    [[ "$args" == *"{{.Names}}"* ]] || {
      echo "wrong format arg: $args" >&2; return 1
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
  [[ "$output" == *"already exists"* ]]
}

# ── _clode_pick_container ────────────────────────────────

@test "_clode_pick_container: returns 1 when tty unavailable" {
  docker() { return 0; }
  export CLODE_TTY="/nonexistent/tty/$$"
  run _clode_pick_container "myproject" "myproject-2"
  unset CLODE_TTY
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot pick non-interactively"* ]]
}

@test "_clode_pick_container: echoes chosen name on valid selection" {
  docker() {
    printf 'myproject\tUp 2 hours\n'
    printf 'myproject-2\tUp 5 minutes\n'
  }
  local tmpfile
  tmpfile="$(mktemp)"
  printf '2\n' > "$tmpfile"
  export CLODE_TTY="$tmpfile"
  run _clode_pick_container "myproject" "myproject-2"
  unset CLODE_TTY
  rm -f "$tmpfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"myproject-2"* ]]
}

@test "_clode_pick_container: returns 1 after 3 invalid inputs" {
  docker() { return 0; }
  local tmpfile
  tmpfile="$(mktemp)"
  printf 'x\nx\nx\n' > "$tmpfile"
  export CLODE_TTY="$tmpfile"
  run _clode_pick_container "myproject" "myproject-2"
  unset CLODE_TTY
  rm -f "$tmpfile"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too many invalid"* ]]
}

# ── _clode_new label parsing ──────────────────────────────
# Test the label-matching regex used inside _clode_new.
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$

_is_label() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]]
}

@test "label pattern: simple word matches" {
  run _is_label "fix-auth"
  [ "$status" -eq 0 ]
}

@test "label pattern: slash-separated path matches" {
  run _is_label "fix/auth"
  [ "$status" -eq 0 ]
}

@test "label pattern: dot matches" {
  run _is_label "feat.login"
  [ "$status" -eq 0 ]
}

@test "label pattern: multi-word with space does not match" {
  run _is_label "fix the bug"
  [ "$status" -ne 0 ]
}

@test "label pattern: starts with dash does not match" {
  run _is_label "-bad"
  [ "$status" -ne 0 ]
}

@test "label pattern: empty string does not match" {
  run _is_label ""
  [ "$status" -ne 0 ]
}

# ── _clode_new ────────────────────────────────────────────

@test "_clode_new: uses labeled name when label arg given" {
  _clode_load_config() { :; }
  _clode_build_port_args() { _CLODE_PORT_ARGS=(); _CLODE_PORT_EXTRA=(); _CLODE_PORT_LINES=(); }
  # Output --name <name> so we can verify which name docker was called with
  _clode_base_args() { printf -- '--name\n%s\n' "$1"; }
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  docker_args=""
  docker() { docker_args="$*"; }
  CLODE_IMAGE="test-image"
  _clode_new "fix-auth"
  [[ "$docker_args" == *"myproject--fix-auth"* ]]
}

@test "_clode_new: uses auto-numbered name when first arg is not a label" {
  _clode_load_config() { :; }
  _clode_build_port_args() { _CLODE_PORT_ARGS=(); _CLODE_PORT_EXTRA=(); _CLODE_PORT_LINES=(); }
  _clode_base_args() { printf -- '--name\n%s\n' "$1"; }
  _clode_name() { echo "myproject"; }
  _clode_exists() { return 1; }
  docker_args=""
  docker() { docker_args="$*"; }
  CLODE_IMAGE="test-image"
  # Multi-word arg doesn't match label pattern — should auto-number
  _clode_new "fix the login bug"
  [[ "$docker_args" == *"myproject-2"* ]]
}

@test "_clode_new: returns 1 when _clode_next_name fails" {
  _clode_load_config() { :; }
  _clode_next_name() { echo "clode: already exists" >&2; return 1; }
  run _clode_new "fix-auth"
  [ "$status" -ne 0 ]
}

# ── _clode_attach branching ───────────────────────────────

@test "_clode_attach: errors when no containers running" {
  _clode_running_for_path() { return 0; }  # outputs nothing
  run _clode_attach
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running container"* ]]
}

# ── _clode_stop branching ─────────────────────────────────

@test "_clode_stop: errors when no containers running" {
  _clode_running_for_path() { return 0; }  # outputs nothing
  run _clode_stop
  [ "$status" -ne 0 ]
  [[ "$output" == *"no container found"* ]]
}

# ── smart default branching ───────────────────────────────

@test "smart default: calls _clode_start when no containers running" {
  _clode_running_for_path() { return 0; }  # no output
  _clode_start_called=0
  _clode_start() { _clode_start_called=1; }
  clode
  [ "$_clode_start_called" -eq 1 ]
}

@test "smart default: calls _clode_attach when containers are running" {
  _clode_running_for_path() { echo "myproject"; }
  _clode_attach_called=0
  _clode_attach() { _clode_attach_called=1; }
  clode
  [ "$_clode_attach_called" -eq 1 ]
}

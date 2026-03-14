# `clode new` — Multiple Containers Per Project Directory Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `clode new [label]` subcommand to start additional containers in the same project directory, and update `clode attach`, `clode stop`, and the smart default to show a picker when 2+ containers are running for the current path.

**Architecture:** All changes are in `clode.sh` (a shell file sourced into the user's shell). Three new helpers are added (`_clode_running_for_path`, `_clode_pick_container`, `_clode_next_name`), one new user-facing function (`_clode_new`), and three existing functions are updated (`_clode_attach`, `_clode_stop`, `_clode_help`/dispatcher). Tests use bats (already used for `clode-ws.sh` in `test/clode-ws.bats`). `_clode_pick_container` uses `${CLODE_TTY:-/dev/tty}` for testability.

**Tech Stack:** zsh/bash, bats (Bash Automated Testing System), Docker CLI

**Spec:** `docs/superpowers/specs/2026-03-14-clode-new-container-design.md`

---

## Chunk 1: New helper functions

### Task 1: Create `test/clode.bats` with tests for `_clode_running_for_path` and `_clode_next_name`

**Files:**
- Create: `test/clode.bats`

**Background:** bats tests are run with `bats test/clode.bats`. Each `@test` block runs in a subshell. Shell functions defined inside a test shadow real commands — this is how we mock `docker` and `_clode_exists`. The file under test is sourced in `setup()`. Note: `run cmd` in bats captures all output (stdout + stderr combined) in `$output` and the exit code in `$status`.

- [ ] **Step 1: Write failing tests**

Create `test/clode.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Projects/clode
bats test/clode.bats
```

Expected: multiple FAILs — `_clode_running_for_path` and `_clode_next_name` not yet defined.

- [ ] **Step 3: Commit the test file**

```bash
git add test/clode.bats
git commit -m "test: add failing tests for _clode_running_for_path and _clode_next_name"
```

---

### Task 2: Implement `_clode_running_for_path` and `_clode_next_name` in `clode.sh`

**Files:**
- Modify: `clode.sh` (add two helper functions in the `── Helpers ─` section, after `_clode_free_port`)

- [ ] **Step 1: Add `_clode_running_for_path` to `clode.sh`**

Open `clode.sh`. After the `_clode_free_port` function, add:

```bash
# List names of all RUNNING containers for the current directory (via clode.workspace label).
# Outputs one name per line.
_clode_running_for_path() {
  docker ps --filter "label=clode.workspace=$(pwd)" --format '{{.Names}}' 2>/dev/null
}
```

- [ ] **Step 2: Add `_clode_next_name` to `clode.sh`**

Immediately after `_clode_running_for_path`, add:

```bash
# Return the next available container name for the current directory.
#   _clode_next_name          -> <base>-2, <base>-3, … (never claims <base>)
#   _clode_next_name <label>  -> <base>--<sanitized-label> (errors if taken)
_clode_next_name() {
  local base
  base=$(_clode_name)

  if [[ $# -gt 0 && -n "$1" ]]; then
    # Labeled: sanitize then check availability.
    # Note: '-' is placed first in the negated class to avoid being parsed as a range.
    local label="$1"
    label="${label//\//-}"
    label="${label//[^-a-zA-Z0-9._]/-}"
    local name="${base}--${label}"
    if _clode_exists "$name"; then
      echo "clode: container '$name' already exists." >&2
      return 1
    fi
    echo "$name"
  else
    # Auto-numbered: start at <base>-2, never claim <base>
    local n=2
    local name="${base}-${n}"
    while _clode_exists "$name"; do
      n=$(( n + 1 ))
      name="${base}-${n}"
    done
    echo "$name"
  fi
}
```

- [ ] **Step 3: Run tests**

```bash
bats test/clode.bats
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add clode.sh
git commit -m "feat: add _clode_running_for_path and _clode_next_name helpers"
```

---

### Task 3: Implement `_clode_pick_container` and add its tests

**Files:**
- Modify: `clode.sh` (add `_clode_pick_container` after `_clode_next_name`)
- Modify: `test/clode.bats` (add tests)

**Key design decision:** The function uses `${CLODE_TTY:-/dev/tty}` instead of hardcoded `/dev/tty`. This allows tests to substitute a temp file with scripted input. Never set `CLODE_TTY` in production use.

- [ ] **Step 1: Add tests for `_clode_pick_container`**

Append to `test/clode.bats`:

```bash
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
    # Return tab-separated name/status lines for the status map
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
  # $output combines stdout and stderr; the chosen name is echoed to stdout last
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats test/clode.bats --filter "pick_container"
```

Expected: FAIL — `_clode_pick_container` not yet defined.

- [ ] **Step 3: Implement `_clode_pick_container` in `clode.sh`**

After `_clode_next_name`, add:

```bash
# Show a numbered picker for a list of container names.
# Usage: _clode_pick_container name1 name2 …
# Echoes the chosen name to stdout. Returns 1 on failure.
# Uses ${CLODE_TTY:-/dev/tty} for input — set CLODE_TTY in tests only.
_clode_pick_container() {
  local names=("$@")
  local n=${#names[@]}
  local project
  project=$(basename "$(pwd)")
  local _tty="${CLODE_TTY:-/dev/tty}"

  # Build a name->status map from running containers
  local -A status_map
  while IFS=$'\t' read -r cname cstatus; do
    [[ -n "$cname" ]] && status_map["$cname"]="$cstatus"
  done < <(docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null)

  # Print menu to stderr
  echo "clode: multiple sessions for '${project}':" >&2
  local i
  for (( i=0; i<n; i++ )); do
    local cname="${names[$i]}"
    local cstatus="${status_map[$cname]:-stopped}"
    printf '  %d) %-30s (%s)\n' "$(( i+1 ))" "$cname" "$cstatus" >&2
  done

  # Check tty is available
  if ! true <"$_tty" 2>/dev/null; then
    echo "clode: multiple sessions running for '${project}' — cannot pick non-interactively." >&2
    echo "       Run from a terminal or stop containers manually." >&2
    return 1
  fi

  local attempt=0
  local choice
  while [[ $attempt -lt 3 ]]; do
    printf 'Attach to [1-%d]: ' "$n" >&2
    if ! IFS= read -r choice <"$_tty" 2>/dev/null; then
      echo "clode: failed to read from terminal." >&2
      return 1
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      echo "${names[$(( choice - 1 ))]}"
      return 0
    fi
    echo "clode: invalid selection '$choice' — enter a number between 1 and ${n}." >&2
    attempt=$(( attempt + 1 ))
  done

  echo "clode: too many invalid attempts." >&2
  return 1
}
```

- [ ] **Step 4: Run all tests**

```bash
bats test/clode.bats
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add clode.sh test/clode.bats
git commit -m "feat: add _clode_pick_container helper"
```

---

## Chunk 2: `_clode_new`, updated functions, dispatcher, and help

### Task 4: Add tests for label parsing and implement `_clode_new`

**Files:**
- Modify: `test/clode.bats` (add label-parsing tests)
- Modify: `clode.sh` (add `_clode_new` function)

**Background:** `_clode_new` parses an optional label from `$1` using a regex match, then delegates to the same `docker run` logic as `_clode_start`. The label-parsing logic is straightforward regex — test it in isolation before writing the full function.

- [ ] **Step 1: Add label-parsing tests**

Append to `test/clode.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they pass (pure regex — no implementation needed)**

```bash
bats test/clode.bats
```

Expected: all PASS.

- [ ] **Step 3: Add tests for `_clode_new` behavior**

Append to `test/clode.bats`:

```bash
# ── _clode_new ────────────────────────────────────────────

@test "_clode_new: calls _clode_next_name with label when label arg given" {
  _clode_load_config() { :; }
  _clode_build_port_args() { _CLODE_PORT_ARGS=(); _CLODE_PORT_EXTRA=(); _CLODE_PORT_LINES=(); }
  _clode_base_args() { :; }
  _clode_next_name_called_with=""
  _clode_next_name() { _clode_next_name_called_with="$1"; echo "myproject--fix-auth"; }
  docker() { :; }
  CLODE_IMAGE="test-image"
  _clode_new "fix-auth"
  [ "$_clode_next_name_called_with" = "fix-auth" ]
}

@test "_clode_new: passes non-label first arg as prompt (no label extracted)" {
  _clode_load_config() { :; }
  _clode_build_port_args() { _CLODE_PORT_ARGS=(); _CLODE_PORT_EXTRA=(); _CLODE_PORT_LINES=(); }
  _clode_base_args() { :; }
  _clode_next_name_called_with="UNSET"
  _clode_next_name() { _clode_next_name_called_with="$1"; echo "myproject-2"; }
  docker() { :; }
  CLODE_IMAGE="test-image"
  # Multi-word arg doesn't match label pattern — should be passed as prompt, not label
  _clode_new "fix the login bug"
  [ "$_clode_next_name_called_with" = "" ]
}

@test "_clode_new: returns 1 when _clode_next_name fails" {
  _clode_load_config() { :; }
  _clode_next_name() { echo "clode: already exists" >&2; return 1; }
  run _clode_new "fix-auth"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 4: Run tests to verify new tests fail**

```bash
bats test/clode.bats --filter "_clode_new"
```

Expected: FAIL — `_clode_new` not yet defined.

- [ ] **Step 5: Implement `_clode_new` in `clode.sh`**

Add after `_clode_pick_container`, before `_clode_start`:

```bash
_clode_new() {
  _clode_load_config

  # Extract optional label (first arg matching label pattern)
  local label=""
  if [[ $# -gt 0 && "${1:-}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]]; then
    label="$1"
    shift
  fi

  local bg=0 resume=0 memory="4g" cpus="2"
  local -a ports=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg)           bg=1;               shift ;;
      --resume)       resume=1;           shift ;;
      --memory)       memory="$2";        shift 2 ;;
      --cpus)         cpus="$2";          shift 2 ;;
      -p|--port)      ports+=("-p" "$2"); shift 2 ;;
      *)              break ;;
    esac
  done

  local name
  if ! name=$(_clode_next_name "$label"); then
    return 1
  fi

  local -a claude_flags=("--dangerously-skip-permissions")
  [[ $resume -eq 1 ]] && claude_flags+=("--resume")

  _clode_build_port_args
  local -a _args=()
  while IFS= read -r _line; do [[ -n "$_line" ]] && _args+=("$_line"); done \
    < <(_clode_base_args "$name" "$memory" "$cpus")
  local -a all_args=("${_args[@]}" "${_CLODE_PORT_ARGS[@]}" "${_CLODE_PORT_EXTRA[@]}" "${ports[@]}")

  if [[ $bg -eq 1 ]]; then
    docker run -d "${all_args[@]}" "$CLODE_IMAGE" "${claude_flags[@]}" "$@"
    echo "clode: started '$name' in background"
    for line in "${_CLODE_PORT_LINES[@]}"; do echo "$line"; done

    if [[ "${CLODE_IDLE_TIMEOUT:-0}" -gt 0 ]]; then
      (
        sleep "$CLODE_IDLE_TIMEOUT"
        if _clode_is_running "$name"; then
          docker stop "$name" >/dev/null 2>&1 && \
            echo "clode: '$name' stopped after idle timeout (${CLODE_IDLE_TIMEOUT}s)"
        fi
      ) &
      disown
    fi

    if [[ -n "${NTFY_TOPIC:-}" ]]; then
      (docker wait "$name" >/dev/null 2>&1 && \
        curl -s -o /dev/null "https://ntfy.sh/${NTFY_TOPIC}" \
          -H "Title: clode done" \
          -H "Tags: white_check_mark" \
          -d "$name finished") &
      disown
    fi
  else
    echo "clode: starting '$name'"
    for line in "${_CLODE_PORT_LINES[@]}"; do echo "$line"; done
    docker run -it "${all_args[@]}" "$CLODE_IMAGE" "${claude_flags[@]}" "$@"
  fi
}
```

**Note:** Before writing `_clode_new`, verify the current `_clode_start` function in `clode.sh` to ensure `_clode_new` mirrors it exactly (flags, docker run invocation, idle timeout, ntfy notification). Diff them after writing.

- [ ] **Step 6: Run tests**

```bash
bats test/clode.bats
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add clode.sh test/clode.bats
git commit -m "feat: add _clode_new function and label-parsing tests"
```

---

### Task 5: Update `_clode_attach` to use `_clode_running_for_path` and picker

**Files:**
- Modify: `clode.sh` (`_clode_attach` function)
- Modify: `test/clode.bats` (add branching test)

- [ ] **Step 1: Add test for `_clode_attach` no-container error path**

Append to `test/clode.bats`:

```bash
# ── _clode_attach branching ───────────────────────────────

@test "_clode_attach: errors when no containers running" {
  _clode_running_for_path() { return 0; }  # outputs nothing
  run _clode_attach
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running container"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/clode.bats --filter "attach"
```

Expected: FAIL.

- [ ] **Step 3: Update `_clode_attach` in `clode.sh`**

Replace the existing `_clode_attach` function with:

```bash
_clode_attach() {
  local -a names=()
  while IFS= read -r _n; do [[ -n "$_n" ]] && names+=("$_n"); done \
    < <(_clode_running_for_path)

  local count=${#names[@]}

  if [[ $count -eq 0 ]]; then
    echo "clode: no running container for '$(pwd)'." >&2
    echo "       Run 'clode start' to begin a session." >&2
    return 1
  fi

  local name
  if [[ $count -eq 1 ]]; then
    name="${names[0]}"
  else
    if ! name=$(_clode_pick_container "${names[@]}"); then
      return 1
    fi
  fi

  echo "clode: attaching to '$name'"
  docker exec -it "$name" claude --dangerously-skip-permissions --resume
}
```

- [ ] **Step 4: Run all tests**

```bash
bats test/clode.bats
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add clode.sh test/clode.bats
git commit -m "feat: update _clode_attach to use _clode_running_for_path and picker"
```

---

### Task 6: Update `_clode_stop` to use `_clode_running_for_path` and picker

**Files:**
- Modify: `clode.sh` (`_clode_stop` function)
- Modify: `test/clode.bats` (add branching test)

- [ ] **Step 1: Add test for `_clode_stop` no-container error path**

Append to `test/clode.bats`:

```bash
# ── _clode_stop branching ─────────────────────────────────

@test "_clode_stop: errors when no containers running" {
  _clode_running_for_path() { return 0; }  # outputs nothing
  run _clode_stop
  [ "$status" -ne 0 ]
  [[ "$output" == *"no container found"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/clode.bats --filter "stop"
```

Expected: FAIL.

- [ ] **Step 3: Update `_clode_stop` in `clode.sh`**

Replace the existing `_clode_stop` function with:

```bash
_clode_stop() {
  local -a names=()
  while IFS= read -r _n; do [[ -n "$_n" ]] && names+=("$_n"); done \
    < <(_clode_running_for_path)

  local count=${#names[@]}

  if [[ $count -eq 0 ]]; then
    echo "clode: no container found for '$(pwd)'." >&2
    return 1
  fi

  local name
  if [[ $count -eq 1 ]]; then
    name="${names[0]}"
  else
    if ! name=$(_clode_pick_container "${names[@]}"); then
      return 1
    fi
  fi

  docker stop "$name" >/dev/null && docker rm "$name" >/dev/null 2>&1 || true
  echo "clode: stopped '$name'"
}
```

- [ ] **Step 4: Run all tests**

```bash
bats test/clode.bats
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add clode.sh test/clode.bats
git commit -m "feat: update _clode_stop to use _clode_running_for_path and picker"
```

---

### Task 7: Update smart default, dispatcher, and help text

**Files:**
- Modify: `clode.sh` (smart default in `clode()`, dispatcher `case`, `_clode_help`)

- [ ] **Step 1: Update the smart default in `clode()`**

Find the `*)` catch-all in the `clode()` function. It currently calls `_clode_name` and branches on `_clode_is_running`. Replace it with:

```bash
    *)
      # Smart default: attach (with picker if 2+) if any running, else start new
      local -a _names=()
      while IFS= read -r _n; do [[ -n "$_n" ]] && _names+=("$_n"); done \
        < <(_clode_running_for_path)
      if [[ ${#_names[@]} -eq 0 ]]; then
        echo "clode: no running container — starting new session"
        _clode_start "$@"
      else
        echo "clode: container(s) running — attaching"
        _clode_attach
      fi
      ;;
```

- [ ] **Step 2: Add `new` case to the dispatcher**

In the `clode()` case statement, add before the `*)` catch-all:

```bash
    new)
      shift
      _clode_new "$@"
      ;;
```

- [ ] **Step 3: Update `_clode_help`**

In the SUBCOMMANDS section add after the `start` line:
```
  new [label] [flags] [prompt]  Start an additional session in this directory
```

In the EXAMPLES section add:
```
  clode new                    Start a second session (auto-named myproject-2)
  clode new fix-auth           Start a second session labeled 'fix-auth'
  clode new --bg "run tests"   Background session with no label
```

- [ ] **Step 4: Add tests for smart default branching**

Append to `test/clode.bats`:

```bash
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
```

- [ ] **Step 5: Run tests to verify new tests fail**

```bash
bats test/clode.bats --filter "smart default"
```

Expected: FAIL — smart default still uses old `_clode_is_running` logic.

- [ ] **Step 6: Update the smart default, dispatcher, and help (as described in steps 1-3 above)**

- [ ] **Step 7: Run all tests**

```bash
bats test/clode.bats
```

Expected: all PASS.

- [ ] **Step 8: Smoke test (manual)**

```bash
source ~/Projects/clode/clode.sh
clode help | grep -A3 "new "
```

Expected output includes:
```
  new [label] [flags] [prompt]  Start an additional session in this directory
```

- [ ] **Step 9: Commit**

```bash
git add clode.sh test/clode.bats
git commit -m "feat: add clode new subcommand, update dispatcher and help"
```

---

### Task 8: Final integration test and README update

**Files:**
- Modify: `README.md` (add `new` to the Commands section)

- [ ] **Step 1: Add `clode new` to README**

In `README.md`, find the `### Commands` section. After the `clode start` command block, add:

````markdown
### `clode new` — start an additional session

```bash
clode new [label]
```

Start a new container in the current project directory alongside any already-running sessions. The new container gets an auto-numbered name (`myproject-2`, `myproject-3`, …) or a labeled name if supplied.

```bash
clode new                  # auto-named: myproject-2
clode new fix-auth         # labeled: myproject--fix-auth
clode new --bg "run tests" # background, no label
```

When 2 or more sessions are running, `clode`, `clode attach`, and `clode stop` show a numbered picker to choose which session to interact with.
````

- [ ] **Step 2: Run full test suite**

```bash
bats test/clode.bats && bats test/clode-ws.bats
```

Expected: all PASS, no regressions in `clode-ws.bats`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document clode new subcommand in README"
```

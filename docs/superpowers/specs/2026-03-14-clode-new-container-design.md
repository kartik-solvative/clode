# Design: `clode new` — Multiple Containers Per Project Directory

**Date:** 2026-03-14
**Status:** Approved

## Problem

`clode` enforces one container per directory by deriving a deterministic name from the path. There is no way to run two independent Claude tasks in parallel on the same codebase without using separate worktrees.

## Goal

Allow users to start an additional container in the same directory (or worktree) with a single command, and gracefully handle attachment/stop when multiple containers are running.

## New Subcommand

```
clode new [label] [flags] [prompt]
```

- **No label:** always auto-numbers starting at `<base>-2` (e.g., `myproject-2`, `myproject-3`, …). The base name `myproject` is reserved for `clode start` / smart default. Creating `myproject-2` before `myproject` ever exists is valid and intentional.
- **With label:** uses `myproject--<label>` (double-dash separator distinguishes labeled from auto-numbered names)
- Accepted flags (same as `clode start`): `--bg`, `--resume`, `--memory <mem>`, `--cpus <n>`, `-p <host:container>` (publish an extra port)
- `--resume` passes through to Claude unchanged. Since the same project directory is mounted, Claude can resume a prior conversation from its session history.

### Label parsing

A label is the first positional argument **if and only if** it matches `^[a-zA-Z0-9][a-zA-Z0-9._/-]*$` (no spaces, no shell-special characters). An argument that does not match (e.g. a multi-word quoted prompt) is treated as the start of the Claude prompt and passed through unchanged.

### Label sanitization

The label is sanitized before use as a container name suffix. Substitution rules applied in order:
1. `/` → `-`
2. Any remaining character outside `[a-zA-Z0-9._-]` → `-`
3. `.` and `-` are preserved as-is (Docker allows both)

Example: `fix/auth` → `fix-auth`; `feat.login` → `feat.login`.

Collision between raw labels that sanitize to the same string (e.g., `fix/auth` and `fix-auth`) is out of scope — the second caller receives a "container already exists" error.

## Picker

When `clode` (smart default), `clode attach`, or `clode stop` encounters 2+ running containers for the current path, a numbered menu is shown:

```
clode: multiple sessions for 'myproject':
  1) myproject           (up 2h14m)
  2) myproject-2         (up 8m)
  3) myproject--fix-auth (up 31m)
Attach to [1-3]: _
```

Containers are discovered via the existing `clode.workspace` Docker label. Selection reads from `/dev/tty`. If `/dev/tty` cannot be opened, the picker prints an error to stderr and returns 1:

```
clode: multiple sessions running for 'myproject' — cannot pick non-interactively.
       Run from a terminal or stop containers manually.
```

On invalid input (non-numeric or out-of-range), the picker re-prompts up to 3 times, then returns 1. If a container listed in the menu has stopped by the time the status is fetched, its status is shown as `(stopped)` rather than an uptime string. If the user selects a stopped container, the subsequent `docker exec` or `docker stop` will fail with Docker's own error message — no special handling required.

The smart default and `clode attach` never offer "start new" through the picker — use `clode new` explicitly for that.

## Known Limitations

- `clode stop` stops one container at a time. To stop all sessions for a directory, run `clode stop` repeatedly or `docker stop` them manually.
- `--resume` with multiple prior sessions relies on Claude's own session selection logic; `clode` does not influence which session Claude resumes.

## Implementation Changes (all in `clode.sh`)

### Existing helpers (already in `clode.sh`, unchanged)

`_clode_exists "$name"` — checks all container states (`docker ps -aq`). Used by `_clode_next_name`.

### New helpers

**`_clode_running_for_path()`**
Lists names of all *running* containers whose `clode.workspace` label matches `$(pwd)`. Outputs one name per line:
```sh
docker ps --filter "label=clode.workspace=$(pwd)" --format '{{.Names}}'
```

**`_clode_pick_container name1 name2 …`**
Positional args are container names. Queries Docker for status of each via `docker ps --format '{{.Names}}\t{{.Status}}'`; shows `(stopped)` for any name not found. Prints numbered menu to stderr. Reads selection from `/dev/tty`; re-prompts up to 3 times on invalid input. Returns 1 on `/dev/tty` open failure or after 3 invalid inputs. Echoes chosen name to stdout on success.

**`_clode_next_name [label]`**
- With label: sanitize the raw label, construct `<base>--<sanitized-label>`. If `_clode_exists` returns true for that constructed name (checked against the sanitized form), print error to stderr and return 1.
- Without label: iterate `<base>-2`, `<base>-3`, … (never `<base>`) until `_clode_exists` returns false; return that name.

### New function

**`_clode_new()`**
1. Calls `_clode_load_config`
2. If first arg matches label pattern, extracts it and shifts
3. Parses flags: `--bg`, `--resume`, `--memory`, `--cpus`, `-p`/`--port`
4. Calls `_clode_next_name [label]`; returns 1 on error
5. Runs the same `docker run` logic as `_clode_start()` with the resolved name

### Updated functions

**`_clode_attach()`** (fully updated — all branches use `_clode_running_for_path()` output, not `_clode_name()`)
1. Calls `_clode_running_for_path()` → array of names
2. Branches:
   - 0 → existing "no container" error (unchanged)
   - 1 → `docker exec -it <discovered-name> claude --dangerously-skip-permissions --resume` (same behavior as today, using discovered name)
   - 2+ → `_clode_pick_container "${names[@]}"` → `docker exec` chosen name

**`_clode_stop()`**
1. Calls `_clode_running_for_path()` → array of names
2. Branches:
   - 0 → existing "no container found" error
   - 1 → existing `docker stop + docker rm` logic
   - 2+ → `_clode_pick_container "${names[@]}"` → `docker stop + docker rm` chosen name

**Smart default (`clode()`)**
- 0 running → `_clode_start "$@"` (unchanged)
- 1 running → `_clode_attach` (correct by virtue of `_clode_attach` being updated above)
- 2+ running → `_clode_attach` (picker lives there; no duplication)

**`_clode_help()`**
Add to SUBCOMMANDS:
```
  new [label] [flags] [prompt]  Start an additional session in this directory
```
Add to EXAMPLES:
```
  clode new                    Start a second session (auto-named myproject-2)
  clode new fix-auth           Start a second session labeled 'fix-auth'
  clode new --bg "run tests"   Background session, no label
```

**`clode()` dispatcher**
Add before the `*` catch-all:
```sh
new)
  shift
  _clode_new "$@"
  ;;
```

## Naming Examples

| Command | Existing containers | Resulting name |
|---|---|---|
| `clode new` | none | `myproject-2` |
| `clode new` | `myproject-2` | `myproject-3` |
| `clode new` | `myproject-2`, `myproject-3` | `myproject-4` |
| `clode new fix-auth` | none | `myproject--fix-auth` |
| `clode new refactor/db` | none | `myproject--refactor-db` |
| `clode new "fix the login bug"` | none | `myproject-2` (spaces → not a label; arg passed as Claude prompt) |

## Out of Scope

- `clode list` changes (existing label-based listing already shows all containers for a path)
- Renaming running containers
- Auto-labeling from prompt text
- Collision between raw labels that sanitize to the same string
- "Stop all" for multiple containers
- Claude session selection behavior with `--resume`

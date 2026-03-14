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

- **No label:** auto-picks the next available name (`myproject`, `myproject-2`, `myproject-3`, …)
- **With label:** uses `myproject--<label>` (double-dash separator distinguishes labeled from auto-numbered names)
- Accepts all existing flags: `--bg`, `--resume`, `--memory`, `--cpus`, `-p`

## Picker

When `clode` (smart default), `clode attach`, or `clode stop` encounters 2+ running containers for the current path, a numbered menu is shown:

```
clode: multiple sessions for 'myproject':
  1) myproject           (up 2h14m)
  2) myproject-2         (up 8m)
  3) myproject--fix-auth (up 31m)
Attach to [1-3]: _
```

Containers are discovered via the existing `clode.workspace` Docker label, not by name-matching. Selection is plain shell `read` — no extra dependencies.

## Implementation Changes (all in `clode.sh`)

### New helpers

**`_clode_running_for_path()`**
Lists names of all *running* containers whose `clode.workspace` label matches `$(pwd)`. Outputs one name per line.

**`_clode_pick_container(names… )`**
Accepts a list of container names, queries Docker for uptime of each, prints the numbered menu to stderr, reads a selection, echoes the chosen name to stdout.

**`_clode_next_name([label])`**
Given an optional label:
- With label: returns `<base>--<label>` (errors if that name already exists)
- Without label: iterates `<base>`, `<base>-2`, `<base>-3`, … until a free name is found; returns it

### New function

**`_clode_new()`**
Parses an optional positional label (first arg not starting with `-`) plus the standard flags, calls `_clode_next_name()` to get a container name, then runs the same `docker run` logic as `_clode_start()`.

### Updated functions

**`_clode_attach()`**
Calls `_clode_running_for_path()`. Branches:
- 0 running → existing "no container" error
- 1 running → existing direct `docker exec` logic
- 2+ running → `_clode_pick_container()`, then `docker exec` on the chosen name

**`_clode_stop()`**
Calls `_clode_running_for_path()`. Branches:
- 0 running → existing "no container" error
- 1 running → existing `docker stop` logic
- 2+ running → `_clode_pick_container()`, then stop the chosen container

**Smart default (`clode()`)**
- 0 running → start new (existing)
- 1 running → attach directly (existing)
- 2+ running → `_clode_pick_container()`, then attach

**`_clode_help()`**
Add `new [label]` to the SUBCOMMANDS section and EXAMPLES.

**`clode()` dispatcher**
Add `new) shift; _clode_new "$@" ;;` case.

## Naming Examples

| Command | Container name |
|---|---|
| `clode new` (first) | `myproject` |
| `clode new` (second) | `myproject-2` |
| `clode new fix-auth` | `myproject--fix-auth` |
| `clode new refactor/db` | `myproject--refactor-db` (slashes replaced with dashes) |

## Out of Scope

- `clode list` changes (existing label-based listing already shows all containers for a path)
- Renaming running containers
- Auto-labeling from prompt text

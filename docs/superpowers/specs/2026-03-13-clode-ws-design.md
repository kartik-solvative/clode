# clode-ws Design Spec

**Date:** 2026-03-13
**Status:** Draft

---

## Overview

`clode-ws` is a tmux-based workspace manager for Claude Code development. It organises terminals (both host shells and clode Docker containers) by project and git worktree, with fzf-powered navigation and full lifecycle management.

Both `cws` (short alias) and `clode-ws` invoke the same command.

---

## Hierarchy

```
Project
└── Worktree (main or .worktrees/<branch>)
    ├── Host terminal(s)   — plain zsh in the worktree dir
    └── Clode terminal(s)  — Docker container running Claude Code
```

---

## File Structure

```
~/Projects/clode/
└── clode-ws.sh          # new file — sourced from ~/.zshrc

~/.zshrc                 # adds: source .../clode-ws.sh
~/.config/ghostty/config # adds: keybind for cws navigator
```

No state file — all state is derived from:
- tmux sessions (active projects)
- `git worktree list` (worktrees per project)
- tmux window names (which terminals exist)

**Constraint:** Projects must live directly under `~/Projects/<project-name>/`. The project name is always the final path segment. If a project directory is renamed on disk, the tmux session becomes orphaned (known limitation — user must `clode-ws kill` and re-open).

---

## tmux Convention

| Concept | tmux mapping |
|---------|-------------|
| Project | Session named `cws-<project>` |
| Worktree + terminal | Window named `<worktree>:<type>-<n>` |

Window name uses `:` as separator (not `/`) to avoid ambiguity in tmux target syntax and shell parsing.

Example:
```
tmux session: cws-focusreader
  window 1:  main:host-1
  window 2:  main:host-2
  window 3:  main:clode-1
  window 4:  feature-auth:host-1
  window 5:  feature-auth:clode-1
```

### Window name grammar

```
<worktree-slug>:<type>-<n>

worktree-slug  = sanitise(branch-name)
               = strip leading ".worktrees/"
               + replace "/" and whitespace with "-"

type           = "host" | "clode"
n              = 1-based integer, incremented per new terminal of that type
```

Examples:
- branch `main`             → slug `main`
- branch `feature/auth`     → slug `feature-auth`
- worktree `.worktrees/fix/issue-42` → slug `fix-issue-42`

---

## Worktrees

- Stored at: `~/Projects/<project>/.worktrees/<branch>/`
- Created by `clode-ws` via: `git worktree add .worktrees/<branch-slug> -b <branch>`
- Removed by `clode-ws` via: `git worktree remove .worktrees/<branch-slug>` + closes its tmux windows
- Branch name is sanitised (slashes → hyphens) for the directory name

---

## Clode Container Naming

Containers are named `cws-<project>-<worktree-slug>` to:
1. Avoid collisions with standalone `clode` containers (which use bare `<project>` name)
2. Avoid collisions across worktrees of the same project

```
cws-focusreader-main
cws-focusreader-feature-auth
cws-payments-api-main
```

Standalone `clode` continues to name containers `<project>` (e.g., `focusreader`). The two tools can run simultaneously without conflict because their naming prefixes differ.

The worktree directory is mounted as `/workspace` in the container.

**New** clode terminals always start fresh — new container, new Claude conversation, no `--resume`. The `fg` reattach path is the only exception: it re-enters an existing running container's conversation via `--resume`.

### Container lifecycle

`clode-ws`-managed containers do **not** use `--rm`. They persist until explicitly removed by:
- `clode-ws kill <project>` — removes all containers for the project
- `delete worktree` action in the navigator — removes containers for that worktree
- `clode-ws prune` — removes all stopped `cws-*` containers

This allows `fg` to reattach to a container even after detaching.

---

## Commands

```
clode-ws / cws                  Open fzf navigator
clode-ws new <project>          Create tmux session for a project and open navigator
clode-ws kill <project>         Prompt Y/N, then kill session + stop/remove all its containers
clode-ws kill --force <project> Kill without prompt (--force must precede the project name)
clode-ws list                   List all active cws sessions
clode-ws prune                  Remove all non-running cws-* Docker containers (exited, created, or dead)
```

**`clode-ws new` vs navigator auto-create:**
- `clode-ws new <project>` — creates the session and immediately opens the navigator at the worktree step for that project. Use when starting fresh from the command line.
- Navigator — auto-creates the session on first selection if it doesn't exist yet. No difference in end state; `new` just skips the project-selection step.

### Navigator Actions (per worktree)

```
[running]  <worktree>:host-<n>    → switch tmux window to it
[running]  <worktree>:clode-<n>   → switch tmux window to it
[detached] <worktree>:clode-<n>   → offer fg (reattach) or delete
                                    ("detached" = tmux pane gone, Docker container still running)
+ new host terminal               → new tmux window, zsh cd'd to worktree dir
+ new clode terminal              → new tmux window, docker run fresh clode
+ new worktree                    → prompt for branch name → git worktree add
+ delete worktree                 → confirm Y/N, git worktree remove + kill windows + remove containers
```

### bg / fg for clode terminals

- **bg** — user presses `Ctrl+B D` (standard tmux detach) or switches to another window; container keeps running; ntfy notification fires on Claude exit
- **fg** — select a `[detached]` clode terminal in navigator → runs `docker exec -it <container> claude --dangerously-skip-permissions --resume` to reattach to the existing container's conversation. Only valid while the container is still running (not removed).

---

## Navigator UX

Invoked by `cws` or `Ctrl+\` in Ghostty:

```
Step 1: fzf — pick project
        Sources: union of ~/Projects/* directories (git repos only) and active cws-* sessions
        - Non-git dirs in ~/Projects/ are silently skipped (no warning — ensure your project has a .git dir)
        - Active sessions with no matching ~/Projects/ dir are shown with a [tmux only] label
        - Sort: active sessions first, then alphabetical by project name

Step 2: fzf — pick worktree
        From: git worktree list in the project dir (main always listed first)

Step 3: fzf — pick terminal or action
        Shows existing windows for that worktree + creation/management options
```

If no tmux session exists for the selected project, it is created automatically before Step 2.

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| `~/Projects/<project>` does not exist | `clode-ws new`: print error and exit |
| Project is not a git repo | Skipped in navigator Step 1; error if passed to `new` |
| `git worktree add` fails (branch exists, dirty state) | Print git's error message, return to navigator |
| `tmux new-session` when session already exists | Attach to existing session instead of erroring |
| Docker container name already exists (e.g. crash remnant) | Run `docker rm <name>` before `docker run`; print warning |
| `delete worktree` with active attached window | Switch tmux client to `main:host-1` before closing windows |
| `fg` on a container that no longer exists | Print "Container <name> not found — it may have exited. Use 'new clode terminal' to start fresh." |
| `clode-ws kill` on non-existent session | Print warning, still attempt `docker rm` cleanup |

---

## Ghostty Integration

Add to `~/.config/ghostty/config`:
```
keybind = ctrl+\=text:cws\n
```

`Ctrl+\` is chosen over `Ctrl+W` to avoid overriding the standard readline "delete word backward" binding and Ghostty's own close-surface shortcut.

---

## Compatibility

`clode` continues to work standalone. Container names never conflict (`cws-*` prefix vs bare project name). Both tools share the same `CLAUDE_CODE_OAUTH_TOKEN` and Docker image.

---

## Out of Scope

- GUI / TUI beyond fzf
- Remote/SSH sessions
- Saving/restoring tmux layout across reboots
- Projects outside `~/Projects/`

# cws TUI Design Spec

**Date:** 2026-03-13
**Status:** Draft

---

## Overview

`cws-tui` is a Go-based terminal UI that replaces the fzf navigator in `clode-ws`. It provides a persistent split-view workspace manager: a tree of projects, worktrees, and terminals on the left, with a live preview of the selected terminal on the right.

`clode-ws.sh` keeps all existing shell commands unchanged. Only the fzf navigator is replaced.

---

## Layout

```
┌─────────────────────────────────────────────────────────┐
│  Ghostty — cws tab                                       │
│ ┌───────────────────┬───────────────────────────────────┐│
│ │ workspaces        │ focusreader › main › clode-1      ││
│ │                   │                                   ││
│ │ ▼ focusreader     │  live preview (tmux capture-pane) ││
│ │   ▼ main          │  refreshed every 2s               ││
│ │     ● clode-1 ◀── │                                   ││
│ │     ● host-1      │                                   ││
│ │   ▼ feature-auth  │                                   ││
│ │     ● host-1      │                                   ││
│ │     ● clode-1     │  ↵ jump into this terminal        ││
│ │ ▶ payments-api    │                                   ││
│ └───────────────────┴───────────────────────────────────┘│
│  Ctrl+A  action  │  space  palette  │  ↑↓  navigate      │
└─────────────────────────────────────────────────────────┘
```

The split is rendered entirely by `cws-tui` using bubbletea/lipgloss — it is a single process occupying a single tmux pane in session `cws-ui`. There is no second tmux pane for the preview; the binary draws both columns itself. `tmux capture-pane` output is fetched by the binary and rendered in the right column.

---

## Navigation Flow

```
any terminal
  → Ctrl+\  → cws Ghostty tab  (attaches to cws-ui tmux session)
  → ↑↓ navigate tree
  → ↵ on a terminal  → Ghostty tab switches to that project session
  → Ctrl+\  → back to cws tab
```

`Ctrl+\` is already bound in Ghostty config to run `cws`. From inside a project terminal, pressing `Ctrl+\` switches the Ghostty tab back to the `cws-ui` session.

---

## Tree Structure

```
Project                    (cws-<project> tmux session — may or may not exist)
└── Worktree               (git worktree, slug-named)
    ├── host-N   ●         (tmux window: <slug>:host-N)
    └── clode-N  ●         (tmux window: <slug>:clode-N, Docker container)
```

### Status indicators

| Dot | Meaning | Applies to |
|-----|---------|-----------|
| `●` green | tmux window exists and is active | host and clode terminals |
| `●` yellow | tmux window gone, Docker container still running | clode terminals only |
| `●` grey | no tmux window, no running container | clode terminals only |

**Detached** means the tmux window is gone but the Docker container is still running. This state is only possible for clode terminals (host terminals have no container — when their tmux window is gone they simply no longer appear in the tree).

### Projects with no active session

The tree sources projects from two places (union):
- `~/Projects/*` directories that are git repos
- Active `cws-*` tmux sessions

If a project exists on disk but has no active `cws-<project>` session, it appears in the tree with a `[no session]` label and a dimmed style. The user creates a session for it via `Ctrl+A n` or `Ctrl+A c` (which auto-creates the session) or `clode-ws new <project>` from any shell.

---

## Interaction Model

### Normal mode (default)

| Key | Action |
|-----|--------|
| `↑` / `↓` | Move selection up/down |
| `←` / `→` | Collapse / expand node |
| `↵` on running terminal | Switch Ghostty tab to that project session |
| `↵` on detached clode terminal | Offer inline choice: `f` fg (reattach) or `d` delete |
| `↵` on `[no session]` project | Auto-creates the `cws-<project>` tmux session, expands the node to show the `main` worktree, and selects it — user then uses `Ctrl+A n` or `Ctrl+A c` to open a terminal |
| `space` | Open command palette |
| `q` | Quit: runs `tmux detach-client` (keeps `cws-ui` alive), returns Ghostty tab to shell |

### Action mode (`Ctrl+A` to enter)

Pressing `Ctrl+A` activates action mode — an overlay appears at the bottom of the left pane listing available keys. Press `Esc` to cancel without acting.

| Key | Action | Prompt |
|-----|--------|--------|
| `n` | New host terminal (in selected worktree) | none (immediate) |
| `c` | New clode terminal (in selected worktree) | none (immediate) |
| `w` | New worktree (in selected project) | `branch:` text input |
| `f` | fg — reattach to selected detached clode terminal | none (immediate, only shown when detached terminal is selected) |
| `d` | Delete selected terminal | `y/N` confirm |
| `D` | Delete selected worktree | `y/N` confirm |
| `X` | Kill project | `y/N` confirm |

**Context sensitivity:** action mode shows only the keys relevant to the currently selected node. For example, `f` only appears when a detached clode terminal is selected; `D` only appears when a worktree or one of its terminals is selected.

Actions that require text input show an inline prompt at the bottom of the left pane. `↵` confirms, `Esc` cancels and returns to normal mode.

### fg (reattach) for detached clode terminals

`fg` runs:
```bash
docker exec -it <container> claude --dangerously-skip-permissions --resume
```
in a new tmux window, then switches the Ghostty tab to that window. This matches the existing `_cws_fg_clode` behaviour in `clode-ws.sh`.

### Command palette (`space`)

A fuzzy-filtered overlay listing all available actions for the currently selected node. Navigated with `↑↓`, executed with `↵`, dismissed with `Esc`.

Each entry shows:
- Action name (e.g. "New host terminal")
- Scope (e.g. "focusreader · main")
- Shortcut hint (e.g. `Ctrl+A n`)

Palette entries are context-filtered: selecting a project node shows project-level actions; selecting a terminal shows terminal-level actions. Actions requiring text input (e.g. new worktree) trigger the same inline prompt as action mode.

---

## Right Pane — Live Preview

The right pane displays the output of the selected terminal captured via:

```bash
tmux capture-pane -t "cws-<project>" -p -e -S -50
```

Window targeting uses the tmux window index looked up at render time (not the window name string directly) to avoid ambiguity with `:` characters in window names:

```bash
# Resolve window index first
tmux list-windows -t "cws-<project>" -F "#{window_index} #{window_name}" \
  | awk -v name="<slug>:<type>-<n>" '$2 == name {print $1}'
# Then capture by index
tmux capture-pane -t "cws-<project>:<index>" -p -e -S -50
```

Refreshed every 2 seconds. Read-only — no keyboard input is routed to this pane. A `live preview · 2s` badge appears in the header.

When a detached clode terminal is selected, the right pane shows the last captured output (from when the window existed) and a `[detached — container still running]` banner. If no prior capture exists, the banner alone is shown.

---

## tmux Session Architecture

| Session | Purpose |
|---------|---------|
| `cws-ui` | Hosts the TUI. Window `cws-panel` has a single pane running `cws-tui`. The binary renders both the tree and the preview columns internally. Created on first `cws` invocation, persists across invocations. |
| `cws-<project>` | Project terminals — unchanged from existing clode-ws convention. |

### Switching to a project terminal

Pressing `↵` on a running terminal runs:
```bash
tmux switch-client -t "cws-<project>:<window-index>"
```
This switches the current tmux client (the Ghostty tab) to the project session.

### `Ctrl+A` and tmux prefix

`Ctrl+A` is used as the TUI action mode key. **This requires the tmux prefix to remain `Ctrl+B` (the tmux default).** If the user has changed their tmux prefix to `Ctrl+A`, the key will be consumed by tmux before reaching the TUI. The `cws` shell function checks the active tmux prefix at startup and warns:

```
warning: your tmux prefix is Ctrl+A — action mode (Ctrl+A) will not work.
Change your tmux prefix to Ctrl+B or edit _CLODE_WS_ACTION_KEY in clode-ws.sh.
```

`_CLODE_WS_ACTION_KEY` is an exported variable (default `\x01`) that the TUI binary reads to know which key triggers action mode. Users with a non-default tmux prefix can override it.

---

## Shell Integration (`clode-ws.sh` changes)

### Removed
- `_cws_navigate_project` — replaced by TUI
- `_cws_navigate_worktree` — replaced by TUI
- `_cws_navigate_terminal` — replaced by TUI

### Modified

**`cws()` shell function:**
```zsh
cws() {
  if ! command -v cws-tui &>/dev/null; then
    echo "cws-tui not found — run: make -C ~/Projects/clode install" >&2
    return 1
  fi
  # Warn if tmux prefix conflicts with action key
  local prefix
  prefix=$(tmux show-option -gv prefix 2>/dev/null)
  if [[ "$prefix" == "C-a" ]]; then
    echo "warning: tmux prefix is Ctrl+A — action mode key conflicts. See clode-ws.sh." >&2
  fi
  # Attach to or create cws-ui session
  if tmux has-session -t cws-ui 2>/dev/null; then
    tmux attach-session -t cws-ui
  else
    tmux new-session -d -s cws-ui -n cws-panel
    tmux send-keys -t cws-ui:cws-panel "cws-tui" Enter
    tmux attach-session -t cws-ui
  fi
}
```

**`clode-ws new <project>`:** Creates the `cws-<project>` session as before, then invokes `cws()` with the project pre-selected (passes project name as `CWS_SELECT_PROJECT` env var to `cws-tui`, which expands and focuses that project node on startup).

### Unchanged
- `clode-ws kill <project>`
- `clode-ws list`
- `clode-ws prune`
- All `_cws_new_host_terminal`, `_cws_new_clode_terminal`, `_cws_fg_clode`, `_cws_add_worktree`, `_cws_delete_worktree` helpers (called by TUI via shell invocation)

---

## Startup and Empty State

| State | Tree shows |
|-------|-----------|
| No `cws-*` sessions, no `~/Projects/*` git repos | Empty tree with hint: "No projects found. Run `clode-ws new <project>` to get started." |
| Projects on disk, no active sessions | Project nodes with `[no session]` label |
| Mix of active sessions and disk-only projects | All shown; active sessions sorted first |

---

## Binary

| Item | Value |
|------|-------|
| Language | Go |
| TUI framework | [bubbletea](https://github.com/charmbracelet/bubbletea) |
| Styling | [lipgloss](https://github.com/charmbracelet/lipgloss) |
| Build output | `~/Projects/clode/bin/cws-tui` (also installed to PATH via `make install`) |
| Invoked by | `cws()` shell function in `clode-ws.sh` |
| Config env var | `CWS_SELECT_PROJECT` — pre-selects a project on startup |
| Action key env var | `_CLODE_WS_ACTION_KEY` — overrides `Ctrl+A` (default `\x01`) |

The binary reads state from tmux (`tmux list-sessions`, `tmux list-windows`) and Docker (`docker ps`) on startup and polls every 2 seconds.

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| `cws-tui` binary not found | `cws` prints error with install instructions and exits |
| tmux prefix is `Ctrl+A` | Warning printed; TUI still launches; action mode unreachable until user overrides |
| tmux not running | TUI starts, tree shows disk-only projects with `[no session]` labels |
| `docker ps` fails | Container status shows `unknown`; tree still renders |
| `tmux switch-client` to non-existent window | TUI shows inline error banner, stays open |
| `git worktree add` fails (branch exists, dirty state) | Error shown below inline prompt; prompt stays open for correction |
| `docker exec` fails on `fg` (container gone) | Inline error: "Container not found — use Ctrl+A c to start fresh." |
| Detached terminal selected, `↵` pressed | Inline menu: `f` fg / `d` delete — no automatic action |

---

## File Structure

```
~/Projects/clode/
├── clode-ws.sh                   # modified: cws() calls binary, fzf nav removed
├── cmd/
│   └── cws-tui/
│       └── main.go               # binary entry point
├── internal/
│   ├── state/
│   │   └── state.go              # reads tmux + Docker state, 2s polling
│   ├── ui/
│   │   ├── tree.go               # left pane: tree component
│   │   ├── preview.go            # right pane: capture-pane preview
│   │   ├── actionmode.go         # Ctrl+A overlay
│   │   ├── palette.go            # space palette overlay
│   │   └── prompt.go             # inline text/confirm prompts
│   └── tmux/
│       └── tmux.go               # tmux command wrappers (list, switch, capture)
├── Makefile                      # `make install` builds binary and adds to PATH
└── bin/
    └── cws-tui                   # compiled binary (gitignored)
```

---

## Out of Scope

- Mouse support
- Scrolling the preview pane
- Editing files from within the TUI
- Remote/SSH sessions
- Any feature currently out of scope in `clode-ws-design.md`

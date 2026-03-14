package ui

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"cws-tui/internal/state"
)

// handleEnter dispatches Enter key based on the selected node.
func handleEnter(m Model) (tea.Model, tea.Cmd) {
	if m.cursor >= len(m.nodes) {
		return m, nil
	}
	n := m.nodes[m.cursor]

	switch n.kind {
	case nodeProject:
		if !n.hasSession {
			// Auto-create session
			return m, createSessionCmd(n.project, m.projectDir(n.project))
		}
		// Expand project node
		m.expandedProjects[n.project] = true
		m.nodes = buildNodes(m.state, m.expandedProjects, m.expandedWorktrees)
		return m, nil

	case nodeTerminal:
		if n.terminal == nil {
			return m, nil
		}
		switch n.terminal.Status {
		case state.StatusRunning:
			session := "cws-" + n.project
			windowName := n.worktree + ":" + n.terminal.Name
			return m, switchClientCmd(session, windowName)
		case state.StatusDetached:
			m.mode = modePrompt
			m.prompt = newDetachedPrompt(n.project, n.worktree, n.terminal)
			return m, nil
		}
	}
	return m, nil
}

// projectDir returns the dir for a project, from state or home default.
func (m Model) projectDir(name string) string {
	for _, p := range m.state.Projects {
		if p.Name == name && p.Dir != "" {
			return p.Dir
		}
	}
	return filepath.Join(os.Getenv("HOME"), "Projects", name)
}

// newDetachedPrompt returns a prompt for fg/delete choice on a detached terminal.
func newDetachedPrompt(project, worktree string, t *state.Terminal) *promptModel {
	container := t.Container
	return newTextPrompt(
		fmt.Sprintf("detached %s — f=fg  d=delete  Esc=cancel", t.Name),
		func(key string) tea.Cmd {
			switch key {
			case "f":
				return fgReattachCmd(project, worktree, container)
			case "d":
				return deleteTerminalCmd(project, worktree, t)
			}
			return nil
		},
	)
}

// switchClientCmd selects a window by name then switches the tmux client to the session.
// Mirrors _cws_goto in clode-ws.sh: select-window first (no TTY needed), then
// switch-client with /dev/tty so tmux can identify the current client.
func switchClientCmd(session, windowName string) tea.Cmd {
	return func() tea.Msg {
		// Step 1: select the window by exact name ("=" avoids ":" being parsed as pane separator).
		selectTarget := session + ":=" + windowName
		if err := exec.Command("tmux", "select-window", "-t", selectTarget).Run(); err != nil {
			return errMsg{fmt.Errorf("select-window %s: %w", selectTarget, err)}
		}
		// Step 2: switch the client to the session (TTY needed to identify which client).
		switchCmd := exec.Command("tmux", "switch-client", "-t", session)
		if tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0); err == nil {
			switchCmd.Stdin = tty
			defer tty.Close()
		}
		if err := switchCmd.Run(); err != nil {
			return errMsg{fmt.Errorf("switch-client %s: %w", session, err)}
		}
		return switchedMsg{}
	}
}

// createSessionCmd creates a new detached cws-<project> tmux session.
func createSessionCmd(project, dir string) tea.Cmd {
	return func() tea.Msg {
		sessionName := "cws-" + project
		if dir == "" {
			dir = filepath.Join(os.Getenv("HOME"), "Projects", project)
		}
		cmd := exec.Command("tmux", "new-session", "-d", "-s", sessionName, "-c", dir, "-n", "main:host-1")
		if err := cmd.Run(); err != nil {
			return errMsg{err}
		}
		return refreshMsg{}
	}
}

// fgReattachCmd runs docker exec in a new tmux window and switches to it.
func fgReattachCmd(project, worktree, container string) tea.Cmd {
	return func() tea.Msg {
		session := "cws-" + project
		windowName := worktree + ":clode-fg"
		// Create new window running docker exec — each arg separate (no shell interpolation)
		cmd := exec.Command("tmux", "new-window",
			"-t", session,
			"-n", windowName,
			"docker", "exec", "-it", container,
			"claude", "--dangerously-skip-permissions", "--resume",
		)
		if err := cmd.Run(); err != nil {
			return errMsg{err}
		}
		// Switch client to the session (tmux will focus the new window)
		switchCmd := exec.Command("tmux", "switch-client", "-t", session)
		switchCmd.Run()
		return switchedMsg{}
	}
}

// deleteTerminalCmd kills a tmux window or removes a stopped Docker container.
func deleteTerminalCmd(project, worktree string, t *state.Terminal) tea.Cmd {
	return func() tea.Msg {
		session := "cws-" + project
		if t.WindowIndex >= 0 {
			target := fmt.Sprintf("%s:%d", session, t.WindowIndex)
			cmd := exec.Command("tmux", "kill-window", "-t", target)
			cmd.Run()
		}
		if t.Container != "" {
			cmd := exec.Command("docker", "rm", "-f", t.Container)
			cmd.Run()
		}
		return refreshMsg{}
	}
}

// deleteWorktreeCmd calls _cws_delete_worktree via clode-ws.sh.
func deleteWorktreeCmd(project, worktree string) tea.Cmd {
	return shellHelperCmd("_cws_delete_worktree", project, worktree)
}

// killProjectCmd calls clode-ws kill <project>.
func killProjectCmd(project string) tea.Cmd {
	return shellHelperCmd("clode-ws", "kill", project)
}

// newWorktreeCmd calls _cws_add_worktree via clode-ws.sh.
func newWorktreeCmd(project, branch string) tea.Cmd {
	return shellHelperCmd("_cws_add_worktree", project, branch)
}

// newHostTerminalCmd calls _cws_new_host_terminal via clode-ws.sh.
func newHostTerminalCmd(project, worktree string) tea.Cmd {
	return shellHelperCmd("_cws_new_host_terminal", project, worktree)
}

// newClodeTerminalCmd calls _cws_new_clode_terminal via clode-ws.sh.
func newClodeTerminalCmd(project, worktree string) tea.Cmd {
	return shellHelperCmd("_cws_new_clode_terminal", project, worktree)
}

// shellHelperCmd sources clode-ws.sh and invokes a shell function.
// All arguments are shell-quoted to prevent injection.
func shellHelperCmd(fn string, args ...string) tea.Cmd {
	return func() tea.Msg {
		cwsScript := os.Getenv("CWS_SCRIPT")
		if cwsScript == "" {
			cwsScript = filepath.Join(os.Getenv("HOME"), "Projects/clode/clode-ws.sh")
		}
		parts := ". " + shellQuote(cwsScript) + " && " + fn
		for _, a := range args {
			parts += " " + shellQuote(a)
		}
		cmd := exec.Command("zsh", "-c", parts)
		cmd.Run()
		return refreshMsg{}
	}
}

// shellQuote single-quote-escapes a string for safe shell interpolation.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

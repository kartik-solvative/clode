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
			if os.Getenv("TMUX") == "" {
				// Running outside tmux: suspend the TUI and attach directly.
				return m, attachSessionCmd(session, windowName)
			}
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

// attachSessionCmd is used when cws-tui is running outside tmux. It selects the
// target window then suspends the TUI and hands the terminal to tmux attach-session.
// When the user detaches (Ctrl+b d), the TUI resumes.
func attachSessionCmd(session, windowName string) tea.Cmd {
	exec.Command("tmux", "select-window", "-t", session+":="+windowName).Run()
	return tea.ExecProcess(
		exec.Command("tmux", "attach-session", "-t", session),
		func(err error) tea.Msg {
			if err != nil {
				return errMsg{err}
			}
			return refreshMsg{}
		},
	)
}

// resolveClient returns the name of the tmux client attached to the session
// that contains $TMUX_PANE (i.e. the session running cws-tui). Falls back to
// the first available client when the session cannot be determined.
func resolveClient() (string, error) {
	pane := os.Getenv("TMUX_PANE")
	var mySession string
	if pane != "" {
		if out, err := exec.Command("tmux", "display-message", "-t", pane, "-p", "#{session_name}").Output(); err == nil {
			mySession = strings.TrimSpace(string(out))
		}
	}
	lcOut, err := exec.Command("tmux", "list-clients", "-F", "#{client_name} #{client_session}").Output()
	if err != nil {
		return "", fmt.Errorf("list-clients: %w", err)
	}
	for _, line := range strings.Split(strings.TrimSpace(string(lcOut)), "\n") {
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		if mySession == "" || parts[1] == mySession {
			return parts[0], nil
		}
	}
	return "", fmt.Errorf("no client for %q (clients: %q)", mySession, strings.TrimSpace(string(lcOut)))
}

// switchClientCmd is used when cws-tui is running inside tmux ($TMUX is set).
// It selects the target window then switches the current tmux client to the session.
// The client is resolved by matching list-clients output against the session that
// cws-tui itself is running in.
func switchClientCmd(session, windowName string) tea.Cmd {
	return func() tea.Msg {
		selectTarget := session + ":=" + windowName
		if err := exec.Command("tmux", "select-window", "-t", selectTarget).Run(); err != nil {
			return errMsg{fmt.Errorf("select-window %s: %w", selectTarget, err)}
		}
		client, err := resolveClient()
		if err != nil {
			return errMsg{err}
		}
		if err := exec.Command("tmux", "switch-client", "-c", client, "-t", session).Run(); err != nil {
			return errMsg{fmt.Errorf("switch-client -c %s -t %s: %w", client, session, err)}
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
		cmd := exec.Command("tmux", "new-window",
			"-t", session,
			"-n", windowName,
			"docker", "exec", "-it", container,
			"claude", "--dangerously-skip-permissions", "--resume",
		)
		if err := cmd.Run(); err != nil {
			return errMsg{fmt.Errorf("new-window: %w", err)}
		}
		client, err := resolveClient()
		if err != nil {
			return errMsg{err}
		}
		if err := exec.Command("tmux", "switch-client", "-c", client, "-t", session).Run(); err != nil {
			return errMsg{fmt.Errorf("switch-client -c %s -t %s: %w", client, session, err)}
		}
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

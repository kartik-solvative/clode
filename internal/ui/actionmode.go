package ui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"cws-tui/internal/state"
)

// contextActions returns keys available for the currently selected node.
func contextActions(m Model) []ActionKey {
	if m.cursor >= len(m.nodes) {
		return nil
	}
	n := m.nodes[m.cursor]

	switch n.kind {
	case nodeProject:
		scope := n.project
		return []ActionKey{
			{Key: "n", Label: "new host terminal", Scope: scope},
			{Key: "c", Label: "new clode terminal", Scope: scope},
			{Key: "w", Label: "new worktree", Scope: scope},
			{Key: "X", Label: "kill project", Scope: scope},
		}
	case nodeWorktree:
		scope := n.project + " · " + n.worktree
		return []ActionKey{
			{Key: "n", Label: "new host terminal", Scope: scope},
			{Key: "c", Label: "new clode terminal", Scope: scope},
			{Key: "w", Label: "new worktree", Scope: scope},
			{Key: "D", Label: "delete worktree", Scope: scope},
			{Key: "X", Label: "kill project", Scope: scope},
		}
	case nodeTerminal:
		scope := n.project + " · " + n.worktree
		keys := []ActionKey{
			{Key: "d", Label: "delete terminal", Scope: scope},
			{Key: "D", Label: "delete worktree", Scope: scope},
			{Key: "X", Label: "kill project", Scope: scope},
		}
		if n.terminal != nil && n.terminal.Status == state.StatusDetached && n.terminal.Type == state.TypeClode {
			keys = append([]ActionKey{{Key: "f", Label: "fg (reattach)", Scope: scope}}, keys...)
		}
		return keys
	}
	return nil
}

// renderActionMode renders the action mode overlay.
func renderActionMode(m Model, width int) string {
	keys := contextActions(m)
	var parts []string
	for _, k := range keys {
		parts = append(parts, k.Key+" "+k.Label)
	}
	overlay := "  Ctrl+A action  |  " + strings.Join(parts, "  |  ") + "  |  Esc cancel"
	_ = width
	return overlay
}

// updateActionModeKey handles key events when in action mode.
func updateActionModeKey(m Model, msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if msg.Type == tea.KeyEsc {
		m.mode = modeNormal
		return m, nil
	}
	if msg.Type == tea.KeyRunes && len(msg.Runes) == 1 {
		// Capture the current node context before modifying mode.
		var n node
		if m.cursor < len(m.nodes) {
			n = m.nodes[m.cursor]
		}
		// Project nodes have no worktree; default to "main".
		worktree := n.worktree
		if worktree == "" {
			worktree = "main"
		}
		switch msg.Runes[0] {
		case 'n':
			m.mode = modeNormal
			return m, newHostTerminalCmd(n.project, worktree)
		case 'c':
			m.mode = modeNormal
			return m, newClodeTerminalCmd(n.project, worktree)
		case 'w':
			project := n.project
			m.mode = modePrompt
			m.prompt = newTextPrompt("branch:", func(branch string) tea.Cmd {
				return newWorktreeCmd(project, branch)
			})
		case 'd':
			project := n.project
			worktree := n.worktree
			terminal := n.terminal
			m.mode = modePrompt
			m.prompt = newConfirmPrompt("delete terminal? y/N", func(confirmed bool) tea.Cmd {
				if confirmed && terminal != nil {
					return deleteTerminalCmd(project, worktree, terminal)
				}
				return nil
			})
		case 'D':
			project := n.project
			worktree := n.worktree
			m.mode = modePrompt
			m.prompt = newConfirmPrompt("delete worktree? y/N", func(confirmed bool) tea.Cmd {
				if confirmed {
					return deleteWorktreeCmd(project, worktree)
				}
				return nil
			})
		case 'X':
			project := n.project
			m.mode = modePrompt
			m.prompt = newConfirmPrompt("kill project? y/N", func(confirmed bool) tea.Cmd {
				if confirmed {
					return killProjectCmd(project)
				}
				return nil
			})
		case 'f':
			m.mode = modeNormal
			if n.terminal != nil {
				return m, fgReattachCmd(n.project, n.worktree, n.terminal.Container)
			}
		}
	}
	return m, nil
}

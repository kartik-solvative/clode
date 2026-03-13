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
		switch msg.Runes[0] {
		case 'n', 'c':
			m.mode = modeNormal
			// Actions wired in Task 9
		case 'w':
			m.mode = modePrompt
			m.prompt = newTextPrompt("branch:", nil)
		case 'd':
			m.mode = modePrompt
			m.prompt = newConfirmPrompt("delete terminal? y/N", nil)
		case 'D':
			m.mode = modePrompt
			m.prompt = newConfirmPrompt("delete worktree? y/N", nil)
		case 'X':
			m.mode = modePrompt
			m.prompt = newConfirmPrompt("kill project? y/N", nil)
		case 'f':
			m.mode = modeNormal
			// Fg action wired in Task 9
		}
	}
	return m, nil
}

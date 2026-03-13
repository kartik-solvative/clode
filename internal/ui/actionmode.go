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
		return []ActionKey{
			{Key: "n", Label: "new host terminal"},
			{Key: "c", Label: "new clode terminal"},
			{Key: "w", Label: "new worktree"},
			{Key: "X", Label: "kill project"},
		}
	case nodeWorktree:
		return []ActionKey{
			{Key: "n", Label: "new host terminal"},
			{Key: "c", Label: "new clode terminal"},
			{Key: "w", Label: "new worktree"},
			{Key: "D", Label: "delete worktree"},
			{Key: "X", Label: "kill project"},
		}
	case nodeTerminal:
		keys := []ActionKey{
			{Key: "d", Label: "delete terminal"},
			{Key: "D", Label: "delete worktree"},
			{Key: "X", Label: "kill project"},
		}
		if n.terminal != nil && n.terminal.Status == state.StatusDetached && n.terminal.Type == state.TypeClode {
			keys = append([]ActionKey{{Key: "f", Label: "fg (reattach)"}}, keys...)
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
			// Prompt wired in Task 7
		case 'd':
			m.mode = modePrompt
		case 'D':
			m.mode = modePrompt
		case 'X':
			m.mode = modePrompt
		case 'f':
			m.mode = modeNormal
			// Fg action wired in Task 9
		}
	}
	return m, nil
}

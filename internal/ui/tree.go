package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"cws-tui/internal/state"
)

var (
	styleSelected = lipgloss.NewStyle().Background(lipgloss.Color("#1e3a4e")).Foreground(lipgloss.Color("#ffffff"))
	styleProject  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#e0e0e0"))
	styleWorktree = lipgloss.NewStyle().Foreground(lipgloss.Color("#aaaaaa"))
	styleTerminal = lipgloss.NewStyle().Foreground(lipgloss.Color("#888888"))
	styleDim      = lipgloss.NewStyle().Faint(true)
	styleGreen    = lipgloss.NewStyle().Foreground(lipgloss.Color("#28c840"))
	styleYellow   = lipgloss.NewStyle().Foreground(lipgloss.Color("#febc2e"))
	styleGrey     = lipgloss.NewStyle().Foreground(lipgloss.Color("#555555"))
	styleHeader   = lipgloss.NewStyle().Background(lipgloss.Color("#1e3347")).Foreground(lipgloss.Color("#7ec8e3")).Padding(0, 1)
)

// renderTree renders the left pane as a string.
func renderTree(m Model, width int) string {
	header := styleHeader.Width(width).Render("workspaces")
	var sb strings.Builder
	sb.WriteString(header)
	sb.WriteRune('\n')
	for i, n := range m.nodes {
		sb.WriteString(renderNode(n, i == m.cursor, width))
		sb.WriteRune('\n')
	}
	return sb.String()
}

// renderNode renders a single tree row.
func renderNode(n node, selected bool, width int) string {
	var row string
	switch n.kind {
	case nodeProject:
		arrow := "▶"
		if n.expanded {
			arrow = "▼"
		}
		label := n.project
		row = fmt.Sprintf("%s %s", arrow, label)
		row = styleProject.Render(row)
	case nodeWorktree:
		arrow := "▶"
		if n.expanded {
			arrow = "▼"
		}
		row = fmt.Sprintf("  %s %s", arrow, n.worktree)
		row = styleWorktree.Render(row)
	case nodeTerminal:
		dot := dotStyle(n.terminal)
		name := ""
		if n.terminal != nil {
			name = n.terminal.Name
		}
		row = fmt.Sprintf("    %s %s", dot, name)
		row = styleTerminal.Render(row)
	}
	if selected {
		row = styleSelected.Width(width).Render(row)
	}
	return row
}

// dotStyle returns a colored status dot for a terminal.
func dotStyle(t *state.Terminal) string {
	if t == nil {
		return styleGrey.Render("●")
	}
	switch t.Status {
	case state.StatusRunning:
		return styleGreen.Render("●")
	case state.StatusDetached:
		return styleYellow.Render("●")
	default:
		return styleGrey.Render("●")
	}
}

// suppress unused variable warning for styleDim
var _ = styleDim

package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"

	"cws-tui/internal/state"
)

var (
	stylePreviewHeader  = lipgloss.NewStyle().Foreground(lipgloss.Color("#555555"))
	stylePreviewActive  = lipgloss.NewStyle().Foreground(lipgloss.Color("#7e7ec8"))
	stylePreviewBadge   = lipgloss.NewStyle().Foreground(lipgloss.Color("#555555")).Border(lipgloss.NormalBorder()).Padding(0, 1)
	stylePreviewBody    = lipgloss.NewStyle().Foreground(lipgloss.Color("#888888"))
	styleDetachedBanner = lipgloss.NewStyle().Foreground(lipgloss.Color("#febc2e"))
	styleJumpHint       = lipgloss.NewStyle().Foreground(lipgloss.Color("#5a7a5a"))
)

// renderPreview renders the right pane.
func renderPreview(m Model, width int) string {
	var sb strings.Builder

	// Header: breadcrumb + badge
	bc := m.PreviewBreadcrumb()
	if bc == "" {
		header := stylePreviewHeader.Render("— select a terminal to preview —")
		sb.WriteString(header)
		sb.WriteRune('\n')
		return sb.String()
	}

	// Build breadcrumb with colored last segment
	parts := strings.Split(bc, " › ")
	var headerParts []string
	for i, p := range parts {
		if i == len(parts)-1 {
			headerParts = append(headerParts, stylePreviewActive.Render(p))
		} else {
			headerParts = append(headerParts, stylePreviewHeader.Render(p))
		}
	}
	badge := stylePreviewBadge.Render("live preview · 2s")
	header := strings.Join(headerParts, stylePreviewHeader.Render(" › ")) + "  " + badge
	sb.WriteString(header)
	sb.WriteRune('\n')

	// Detached banner (if applicable)
	n := m.nodes[m.cursor]
	isDetached := n.terminal != nil && n.terminal.Status == state.StatusDetached
	if isDetached {
		sb.WriteString(styleDetachedBanner.Render("[detached — container still running]"))
		sb.WriteRune('\n')
	}

	// Body: preview text
	if m.preview != "" {
		sb.WriteString(stylePreviewBody.Render(m.preview))
		sb.WriteRune('\n')
	}

	// Footer hint (running terminals only)
	isRunning := n.terminal != nil && n.terminal.Status == state.StatusRunning
	if isRunning {
		sb.WriteString(styleJumpHint.Render("↵ jump into this terminal"))
		sb.WriteRune('\n')
	}

	return sb.String()
}

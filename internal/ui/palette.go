package ui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/charmbracelet/lipgloss"
)

// paletteEntry is one item in the command palette.
type paletteEntry struct {
	Name     string
	Scope    string
	Shortcut string
	Action   tea.Cmd
}

// paletteModel is the state of the command palette overlay.
type paletteModel struct {
	entries []paletteEntry
	filter  string
	cursor  int
}

// newPaletteModel builds palette entries from context action keys.
func newPaletteModel(actions []ActionKey) *paletteModel {
	var entries []paletteEntry
	for _, a := range actions {
		entries = append(entries, paletteEntry{
			Name:     a.Label,
			Scope:    a.Scope,
			Shortcut: "Ctrl+A " + a.Key,
		})
	}
	return &paletteModel{entries: entries}
}

// filtered returns entries whose Name contains the filter string (case-insensitive).
func (p *paletteModel) filtered() []paletteEntry {
	if p.filter == "" {
		return p.entries
	}
	lower := strings.ToLower(p.filter)
	var result []paletteEntry
	for _, e := range p.entries {
		if strings.Contains(strings.ToLower(e.Name), lower) {
			result = append(result, e)
		}
	}
	return result
}

// filteredCount returns the number of filtered entries.
func (p *paletteModel) filteredCount() int {
	return len(p.filtered())
}

// update handles key events for the palette.
// Returns (done bool, cmd tea.Cmd).
func (p *paletteModel) update(msg tea.KeyMsg) (done bool, cmd tea.Cmd) {
	switch msg.Type {
	case tea.KeyEsc:
		return true, nil
	case tea.KeyEnter:
		filtered := p.filtered()
		if p.cursor < len(filtered) {
			cmd = filtered[p.cursor].Action
		}
		return true, cmd
	case tea.KeyDown:
		filtered := p.filtered()
		if p.cursor < len(filtered)-1 {
			p.cursor++
		}
	case tea.KeyUp:
		if p.cursor > 0 {
			p.cursor--
		}
	case tea.KeyBackspace, tea.KeyDelete:
		if len(p.filter) > 0 {
			p.filter = p.filter[:len(p.filter)-1]
			// Reset cursor when filter changes
			if p.cursor >= p.filteredCount() {
				p.cursor = 0
			}
		}
	case tea.KeyRunes:
		p.filter += string(msg.Runes)
		// Reset cursor when filter changes
		if p.cursor >= p.filteredCount() {
			p.cursor = 0
		}
	}
	return false, nil
}

var stylePaletteEntry = lipgloss.NewStyle().Foreground(lipgloss.Color("#cccccc"))
var stylePaletteSelected = lipgloss.NewStyle().Background(lipgloss.Color("#1e3a4e")).Foreground(lipgloss.Color("#ffffff"))
var stylePaletteFilter = lipgloss.NewStyle().Foreground(lipgloss.Color("#7ec8e3"))
var stylePaletteShortcut = lipgloss.NewStyle().Foreground(lipgloss.Color("#555555"))

// renderPaletteOverlay renders the palette as an overlay string.
func renderPaletteOverlay(p *paletteModel, width int) string {
	if p == nil {
		return ""
	}
	var sb strings.Builder
	// Filter line
	filterLine := stylePaletteFilter.Render("> " + p.filter + "█")
	sb.WriteString(filterLine)
	sb.WriteRune('\n')

	filtered := p.filtered()
	for i, entry := range filtered {
		line := entry.Name
		if entry.Scope != "" {
			line = line + "  " + stylePaletteShortcut.Render(entry.Scope)
		}
		if entry.Shortcut != "" {
			line = line + "  " + stylePaletteShortcut.Render(entry.Shortcut)
		}
		if i == p.cursor {
			sb.WriteString(stylePaletteSelected.Width(width).Render(line))
		} else {
			sb.WriteString(stylePaletteEntry.Render(line))
		}
		sb.WriteRune('\n')
	}
	return sb.String()
}

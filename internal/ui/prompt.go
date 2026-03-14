package ui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/charmbracelet/lipgloss"
)

type promptKind int

const (
	promptText    promptKind = iota
	promptConfirm
)

type promptModel struct {
	kind          promptKind
	label         string
	value         string
	err           string
	onTextDone    func(string) tea.Cmd
	onConfirmDone func(bool) tea.Cmd
}

func newTextPrompt(label string, onDone func(string) tea.Cmd) *promptModel {
	return &promptModel{kind: promptText, label: label, onTextDone: onDone}
}

func newConfirmPrompt(label string, onDone func(bool) tea.Cmd) *promptModel {
	return &promptModel{kind: promptConfirm, label: label, onConfirmDone: onDone}
}

// update processes a key. Returns (done, cmd).
// done=true means the prompt is finished (mode should return to normal).
func (p *promptModel) update(msg tea.KeyMsg) (done bool, cmd tea.Cmd) {
	switch p.kind {
	case promptText:
		switch msg.Type {
		case tea.KeyEsc:
			return true, nil
		case tea.KeyEnter:
			if p.value != "" {
				if p.onTextDone != nil {
					cmd = p.onTextDone(p.value)
				}
				return true, cmd
			}
			// Empty value: require non-empty input
			p.err = "branch name required"
		case tea.KeyBackspace, tea.KeyDelete:
			if len(p.value) > 0 {
				p.value = p.value[:len(p.value)-1]
			}
		case tea.KeyRunes:
			p.value += string(msg.Runes)
			p.err = ""
		}
	case promptConfirm:
		// Esc also dismisses the confirm prompt
		if msg.Type == tea.KeyEsc {
			return true, nil
		}
		// Any key exits prompt: y/Y = true, everything else = false
		if msg.Type == tea.KeyRunes && len(msg.Runes) == 1 {
			confirmed := msg.Runes[0] == 'y' || msg.Runes[0] == 'Y'
			if p.onConfirmDone != nil {
				cmd = p.onConfirmDone(confirmed)
			}
		}
		return true, cmd
	}
	return false, nil
}

var stylePrompt = lipgloss.NewStyle().Foreground(lipgloss.Color("#7ec8e3"))

func renderPromptOverlay(p *promptModel, width int) string {
	if p == nil {
		return ""
	}
	var sb strings.Builder
	sb.WriteString(stylePrompt.Render(p.label + " " + p.value))
	if p.err != "" {
		sb.WriteString("  ")
		sb.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("#ff5f57")).Render(p.err))
	}
	return sb.String()
}

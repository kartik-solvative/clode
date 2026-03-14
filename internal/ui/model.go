package ui

import (
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"cws-tui/internal/state"
)

type nodeType int

const (
	nodeProject  nodeType = iota
	nodeWorktree
	nodeTerminal
)

type viewMode int

const (
	modeNormal  viewMode = iota
	modeAction
	modePrompt
	modePalette
)

type node struct {
	kind       nodeType
	project    string
	worktree   string
	terminal   *state.Terminal
	expanded   bool
	hasSession bool // for project nodes: whether cws-<project> session exists
}

// stateMsg carries a fresh *state.State for the 2s poller.
// It is defined as a named type over *state.State so that
// ui.StateMsg(ptr) works as a simple type conversion in main.go and tests.
type stateMsg = StateMsg

// StateMsg is the exported type so main.go and tests can send it via StateMsg(ptr).
type StateMsg *state.State

type errMsg struct{ err error }
type switchedMsg struct{}
type refreshMsg struct{}

// Model is the root bubbletea model.
type Model struct {
	state             *state.State
	nodes             []node
	cursor            int
	mode              viewMode
	preview           string
	width, height     int
	actionKey         byte
	expandedProjects  map[string]bool
	expandedWorktrees map[string]bool
	prompt            *promptModel
	palette           *paletteModel
	errBanner         string
}

// New creates a Model from the given state. All nodes start collapsed.
func New(st *state.State) Model {
	m := Model{
		state:             st,
		expandedProjects:  make(map[string]bool),
		expandedWorktrees: make(map[string]bool),
		actionKey:         0x01, // Ctrl+A default
	}
	// Override action key from env if set.
	if v := os.Getenv("_CLODE_WS_ACTION_KEY"); len(v) > 0 {
		m.actionKey = v[0]
	}
	m.nodes = buildNodes(st, m.expandedProjects, m.expandedWorktrees)
	return m
}

// Exported mode constants for tests.
const ModeNormal = modeNormal
const ModeAction = modeAction
const ModePrompt = modePrompt
const ModePalette = modePalette

func (m Model) PaletteCount() int {
	if m.palette == nil {
		return 0
	}
	return m.palette.filteredCount()
}

func (m Model) PaletteCursor() int {
	if m.palette == nil {
		return 0
	}
	return m.palette.cursor
}

// PromptValue returns the current text value of the active prompt, or "" if none.
func (m Model) PromptValue() string {
	if m.prompt == nil {
		return ""
	}
	return m.prompt.value
}

// Cursor returns the current cursor position (for tests).
func (m Model) Cursor() int { return m.cursor }

// VisibleCount returns the number of visible rows (for tests).
func (m Model) VisibleCount() int { return len(m.nodes) }

// Mode returns current view mode (for tests).
func (m Model) Mode() viewMode { return m.mode }

// ActionKey is one entry in the action mode overlay.
type ActionKey struct{ Key, Label, Scope string }

// ActionModeKeys returns context-sensitive keys for the current node.
func (m Model) ActionModeKeys() []ActionKey { return contextActions(m) }

// PreviewBreadcrumb returns a formatted breadcrumb for the selected terminal node.
func (m Model) PreviewBreadcrumb() string {
	if m.cursor >= len(m.nodes) {
		return ""
	}
	n := m.nodes[m.cursor]
	if n.kind != nodeTerminal {
		return ""
	}
	return n.project + " › " + n.worktree + " › " + n.terminal.Name
}

// WithPreselect expands and focuses the named project on startup.
func (m Model) WithPreselect(project string) Model {
	for i, n := range m.nodes {
		if n.kind == nodeProject && n.project == project {
			m.cursor = i
			m.expandedProjects[project] = true
			m.nodes = buildNodes(m.state, m.expandedProjects, m.expandedWorktrees)
			return m
		}
	}
	return m
}

// Init starts the 2s tick (implemented in main.go poller; this is a no-op stub).
func (m Model) Init() tea.Cmd { return nil }

// Update handles messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case StateMsg:
		m.state = (*state.State)(msg)
		m.nodes = buildNodes(m.state, m.expandedProjects, m.expandedWorktrees)
	case errMsg:
		m.errBanner = msg.err.Error()
	case switchedMsg, refreshMsg:
		// no-op; state poller handles refresh
	case tea.KeyMsg:
		m.errBanner = "" // clear on any key
		if m.mode == modeAction {
			return updateActionModeKey(m, msg)
		}
		if m.mode == modePrompt {
			return m.updatePrompt(msg)
		}
		if m.mode == modePalette {
			return m.updatePalette(msg)
		}
		return m.dispatchKey(msg)
	}
	return m, nil
}

// View renders the full TUI (split pane).
func (m Model) View() string {
	if m.width == 0 {
		return "loading...\n"
	}
	leftWidth := m.width * 35 / 100
	rightWidth := m.width - leftWidth - 1

	left := renderTree(m, leftWidth)

	switch m.mode {
	case modeAction:
		left = renderActionMode(m, leftWidth)
	case modePalette:
		left = renderPaletteOverlay(m.palette, leftWidth)
	case modePrompt:
		left = renderPromptOverlay(m.prompt, leftWidth)
	}

	right := renderPreview(m, rightWidth)
	divider := lipgloss.NewStyle().Foreground(lipgloss.Color("#3a6080")).Render("│")

	row := lipgloss.JoinHorizontal(lipgloss.Top, left, divider, right)
	out := row + "\n" + renderBottomBar(m, m.width)
	if m.errBanner != "" {
		errStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#ff5f57")).Bold(true)
		out += "\n" + errStyle.Render("error: "+m.errBanner)
	}
	return out
}

// dispatchKey handles key events in normal mode.
func (m Model) dispatchKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyUp:
		if m.cursor > 0 {
			m.cursor--
		}
	case tea.KeyDown:
		if m.cursor < len(m.nodes)-1 {
			m.cursor++
		}
	case tea.KeyRight:
		if m.cursor < len(m.nodes) {
			n := m.nodes[m.cursor]
			switch n.kind {
			case nodeProject:
				m.expandedProjects[n.project] = true
			case nodeWorktree:
				key := n.project + "/" + n.worktree
				m.expandedWorktrees[key] = true
			}
			m.nodes = buildNodes(m.state, m.expandedProjects, m.expandedWorktrees)
		}
	case tea.KeyLeft:
		if m.cursor < len(m.nodes) {
			n := m.nodes[m.cursor]
			switch n.kind {
			case nodeProject:
				m.expandedProjects[n.project] = false
			case nodeWorktree:
				key := n.project + "/" + n.worktree
				m.expandedWorktrees[key] = false
			}
			m.nodes = buildNodes(m.state, m.expandedProjects, m.expandedWorktrees)
		}
	case tea.KeyEnter:
		return handleEnter(m)
	case tea.KeyCtrlA:
		m.mode = modeAction
	case tea.KeyRunes:
		if len(msg.Runes) == 1 {
			switch msg.Runes[0] {
			case 'q':
				return m, tea.Quit
			case ' ':
				m.mode = modePalette
				m.palette = newPaletteModel(contextActions(m))
			}
		}
	}
	return m, nil
}

// updatePalette handles key events when the command palette is active.
func (m Model) updatePalette(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	done, cmd := m.palette.update(msg)
	if done {
		m.mode = modeNormal
		m.palette = nil
		return m, cmd
	}
	return m, nil
}

// updatePrompt handles key events when a prompt is active.
func (m Model) updatePrompt(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	done, cmd := m.prompt.update(msg)
	if done {
		m.mode = modeNormal
		m.prompt = nil
		return m, cmd
	}
	return m, nil
}

// buildNodes flattens the state tree into visible rows.
func buildNodes(st *state.State, expandedProjects, expandedWorktrees map[string]bool) []node {
	var nodes []node
	for _, p := range st.Projects {
		pn := node{
			kind:       nodeProject,
			project:    p.Name,
			expanded:   expandedProjects[p.Name],
			hasSession: p.HasSession,
		}
		nodes = append(nodes, pn)
		if !expandedProjects[p.Name] {
			continue
		}
		for _, wt := range p.Worktrees {
			key := p.Name + "/" + wt.Slug
			wn := node{
				kind:     nodeWorktree,
				project:  p.Name,
				worktree: wt.Slug,
				expanded: expandedWorktrees[key],
			}
			nodes = append(nodes, wn)
			if !expandedWorktrees[key] {
				continue
			}
			for i := range wt.Terminals {
				t := &wt.Terminals[i]
				nodes = append(nodes, node{
					kind:     nodeTerminal,
					project:  p.Name,
					worktree: wt.Slug,
					terminal: t,
				})
			}
		}
	}
	return nodes
}

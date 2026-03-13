package ui

import (
	"os"

	tea "github.com/charmbracelet/bubbletea"

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
type stateMsg struct{ st *state.State }

// StateMsg is the exported type alias so main.go can send it.
type StateMsg = stateMsg

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

// Cursor returns the current cursor position (for tests).
func (m Model) Cursor() int { return m.cursor }

// VisibleCount returns the number of visible rows (for tests).
func (m Model) VisibleCount() int { return len(m.nodes) }

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

// Init starts the 2s tick (implemented in main.go poller; this is a no-op stub).
func (m Model) Init() tea.Cmd { return nil }

// Update handles messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case stateMsg:
		m.state = msg.st
		m.nodes = buildNodes(m.state, m.expandedProjects, m.expandedWorktrees)
	case tea.KeyMsg:
		return m.dispatchKey(msg)
	}
	return m, nil
}

// View renders the full TUI (split pane). Implemented fully in Task 10.
func (m Model) View() string {
	return renderTree(m, m.width)
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
	case tea.KeyRunes:
		if len(msg.Runes) == 1 {
			switch msg.Runes[0] {
			case 'q':
				return m, tea.Quit
			case ' ':
				m.mode = modePalette
			}
		}
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

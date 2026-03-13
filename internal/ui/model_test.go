package ui_test

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"cws-tui/internal/state"
	"cws-tui/internal/ui"
)

func twoProjectState() *state.State {
	return &state.State{
		Projects: []state.Project{
			{
				Name:       "focusreader",
				HasSession: true,
				Worktrees: []state.Worktree{{
					Slug: "main",
					Terminals: []state.Terminal{
						{Name: "host-1", Type: state.TypeHost, Status: state.StatusRunning, WindowIndex: 0},
						{Name: "clode-1", Type: state.TypeClode, Status: state.StatusRunning, WindowIndex: 1},
					},
				}},
			},
			{Name: "payments-api", HasSession: false},
		},
	}
}

func TestInitialCursor(t *testing.T) {
	m := ui.New(twoProjectState())
	if m.Cursor() != 0 {
		t.Errorf("want initial cursor 0, got %d", m.Cursor())
	}
	// Both projects collapsed by default: exactly 2 visible nodes
	if m.VisibleCount() != 2 {
		t.Errorf("want 2 visible nodes initially (both collapsed), got %d", m.VisibleCount())
	}
}

func TestNavigateDown(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyDown})
	nm := next.(ui.Model)
	if nm.Cursor() != 1 {
		t.Errorf("want cursor 1 after down, got %d", nm.Cursor())
	}
}

func TestNavigateDoesNotExceedList(t *testing.T) {
	m := ui.New(twoProjectState())
	for i := 0; i < 10; i++ {
		next, _ := m.Update(tea.KeyMsg{Type: tea.KeyDown})
		m = next.(ui.Model)
	}
	last := m.VisibleCount() - 1
	if m.Cursor() != last {
		t.Errorf("want cursor capped at %d (last node), got %d", last, m.Cursor())
	}
}

func TestNavigateUpDoesNotGoBelowZero(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyUp})
	nm := next.(ui.Model)
	if nm.Cursor() != 0 {
		t.Errorf("want cursor stay at 0 on up from top, got %d", nm.Cursor())
	}
}

func TestPreviewBreadcrumb(t *testing.T) {
	m := ui.New(twoProjectState())
	// Expand focusreader
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	// cursor → main worktree
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	// expand main
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	// cursor → host-1
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	// cursor → clode-1
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)

	bc := m.PreviewBreadcrumb()
	if bc == "" {
		t.Fatal("want non-empty breadcrumb when terminal is selected")
	}
	if !strings.Contains(bc, "focusreader") {
		t.Errorf("want 'focusreader' in breadcrumb, got %q", bc)
	}
	if !strings.Contains(bc, "clode-1") {
		t.Errorf("want 'clode-1' in breadcrumb, got %q", bc)
	}
}

func TestExpandCollapse(t *testing.T) {
	m := ui.New(twoProjectState())
	initialCount := m.VisibleCount()
	if initialCount != 2 {
		t.Fatalf("pre-condition: want 2 nodes initially, got %d", initialCount)
	}

	// Press right on focusreader (cursor=0) to expand — adds worktree + terminals
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	nm := next.(ui.Model)
	expandedCount := nm.VisibleCount()
	// focusreader expands to: worktree(main) + 2 terminals + payments-api = 4 total
	if expandedCount <= initialCount {
		t.Errorf("want more nodes after expand, got %d (was %d)", expandedCount, initialCount)
	}

	// Press left on focusreader to collapse
	next2, _ := nm.Update(tea.KeyMsg{Type: tea.KeyLeft})
	nm2 := next2.(ui.Model)
	if nm2.VisibleCount() != initialCount {
		t.Errorf("want %d nodes after collapse, got %d", initialCount, nm2.VisibleCount())
	}
}

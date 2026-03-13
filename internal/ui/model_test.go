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

func hasKey(keys []ui.ActionKey, k string) bool {
	for _, a := range keys {
		if a.Key == k {
			return true
		}
	}
	return false
}

func TestActionModeActivation(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	nm := next.(ui.Model)
	if nm.Mode() != ui.ModeAction {
		t.Errorf("want ModeAction after Ctrl+A, got %v", nm.Mode())
	}
}

func TestActionModeEsc(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	nm := next.(ui.Model)
	next2, _ := nm.Update(tea.KeyMsg{Type: tea.KeyEsc})
	nm2 := next2.(ui.Model)
	if nm2.Mode() != ui.ModeNormal {
		t.Errorf("want ModeNormal after Esc, got %v", nm2.Mode())
	}
}

func TestActionModeContextKeys_ProjectSelected(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	nm := next.(ui.Model)
	keys := nm.ActionModeKeys()
	for _, want := range []string{"n", "c", "w", "X"} {
		if !hasKey(keys, want) {
			t.Errorf("want key %q in action mode for project, got: %v", want, keys)
		}
	}
	if hasKey(keys, "D") {
		t.Error("key 'D' should not appear for project node")
	}
	if hasKey(keys, "f") {
		t.Error("key 'f' should not appear for project node")
	}
}

func TestActionModeContextKeys_WorktreeSelected(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	nm := next.(ui.Model)
	keys := nm.ActionModeKeys()
	for _, want := range []string{"n", "c", "w", "D", "X"} {
		if !hasKey(keys, want) {
			t.Errorf("want key %q in action mode for worktree, got: %v", want, keys)
		}
	}
	if hasKey(keys, "f") {
		t.Error("key 'f' should not appear for non-detached worktree node")
	}
}

func TestActionModeContextKeys_RunningTerminalSelected(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	nm := next.(ui.Model)
	keys := nm.ActionModeKeys()
	if !hasKey(keys, "d") {
		t.Error("want 'd' (delete) for running terminal")
	}
	if hasKey(keys, "f") {
		t.Error("key 'f' should not appear for running terminal (not detached)")
	}
	if !hasKey(keys, "D") {
		t.Error("want 'D' (delete worktree) for terminal node per spec")
	}
}

func navigateToRunningTerminal(t *testing.T, m ui.Model) ui.Model {
	t.Helper()
	var next tea.Model
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	return next.(ui.Model)
}

func TestTextPromptAcceptsInput(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("w")})
	m = next.(ui.Model)
	if m.Mode() != ui.ModePrompt {
		t.Fatalf("want ModePrompt after 'w', got %v", m.Mode())
	}
	for _, c := range "feature-login" {
		next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{c}})
		m = next.(ui.Model)
	}
	if m.PromptValue() != "feature-login" {
		t.Errorf("want PromptValue 'feature-login', got %q", m.PromptValue())
	}
}

func TestTextPromptEnterConfirms(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("w")})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("feat")})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m = next.(ui.Model)
	if m.Mode() != ui.ModeNormal {
		t.Errorf("want ModeNormal after Enter on non-empty prompt, got %v", m.Mode())
	}
}

func TestTextPromptEscCancels(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("w")})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	m = next.(ui.Model)
	if m.Mode() != ui.ModeNormal {
		t.Errorf("want ModeNormal after Esc on prompt, got %v", m.Mode())
	}
}

func TestConfirmPromptYes(t *testing.T) {
	m := navigateToRunningTerminal(t, ui.New(twoProjectState()))
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("d")})
	m = next.(ui.Model)
	if m.Mode() != ui.ModePrompt {
		t.Fatalf("want ModePrompt after 'd', got %v", m.Mode())
	}
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	m = next.(ui.Model)
	if m.Mode() != ui.ModeNormal {
		t.Errorf("want ModeNormal after 'y' confirm, got %v", m.Mode())
	}
}

func TestConfirmPromptNo(t *testing.T) {
	m := navigateToRunningTerminal(t, ui.New(twoProjectState()))
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("d")})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("N")})
	m = next.(ui.Model)
	if m.Mode() != ui.ModeNormal {
		t.Errorf("want ModeNormal after 'N' cancel, got %v", m.Mode())
	}
}

func TestPaletteActivation(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(" ")})
	nm := next.(ui.Model)
	if nm.Mode() != ui.ModePalette {
		t.Errorf("want ModePalette after space, got %v", nm.Mode())
	}
}

func TestPaletteFilterReducesList(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(" ")})
	m = next.(ui.Model)
	totalBefore := m.PaletteCount()
	if totalBefore == 0 {
		t.Fatal("palette should have entries when project is selected")
	}
	for _, c := range "new" {
		next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{c}})
		m = next.(ui.Model)
	}
	if m.PaletteCount() >= totalBefore {
		t.Errorf("filtering by 'new' should reduce entries; was %d, now %d", totalBefore, m.PaletteCount())
	}
}

func TestPaletteEsc(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(" ")})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	nm := next.(ui.Model)
	if nm.Mode() != ui.ModeNormal {
		t.Errorf("want ModeNormal after Esc, got %v", nm.Mode())
	}
}

func TestPaletteCursorNavigation(t *testing.T) {
	m := ui.New(twoProjectState())
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(" ")})
	m = next.(ui.Model)
	if m.PaletteCount() < 2 {
		t.Skip("need at least 2 entries to test cursor movement")
	}
	initialCursor := m.PaletteCursor()
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	if m.PaletteCursor() <= initialCursor {
		t.Errorf("want cursor to advance on Down, was %d now %d", initialCursor, m.PaletteCursor())
	}
}

func TestActionModeContextKeys_DetachedTerminalSelected(t *testing.T) {
	st := &state.State{
		Projects: []state.Project{{
			Name: "focusreader", HasSession: true,
			Worktrees: []state.Worktree{{
				Slug: "main",
				Terminals: []state.Terminal{
					{Name: "host-1", Type: state.TypeHost, Status: state.StatusRunning, WindowIndex: 0},
					{Name: "clode-1", Type: state.TypeClode, Status: state.StatusDetached, WindowIndex: -1,
						Container: "cws-focusreader-main-clode"},
				},
			}},
		}},
	}
	m := ui.New(st)
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m = next.(ui.Model)

	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	nm := next.(ui.Model)
	keys := nm.ActionModeKeys()
	if !hasKey(keys, "f") {
		t.Error("want 'f' (fg reattach) for detached clode terminal")
	}
	if !hasKey(keys, "d") {
		t.Error("want 'd' (delete) for detached terminal")
	}
}

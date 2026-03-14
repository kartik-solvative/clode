package state_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"cws-tui/internal/state"
	"cws-tui/internal/tmux"
)

// fakeTmuxRunner dispatches based on first arg (tmux subcommand).
func fakeTmuxRunner(sessions string, windowsBySession map[string]string) tmux.Runner {
	return func(args ...string) (string, error) {
		switch args[0] {
		case "list-sessions":
			return sessions, nil
		case "list-windows":
			for i, a := range args {
				if a == "-t" && i+1 < len(args) {
					return windowsBySession[args[i+1]], nil
				}
			}
			return "", nil
		case "has-session":
			for i, a := range args {
				if a == "-t" && i+1 < len(args) {
					name := args[i+1]
					for _, s := range strings.Split(sessions, "\n") {
						if strings.TrimSpace(s) == name {
							return "", nil
						}
					}
					return "", os.ErrProcessDone
				}
			}
			return "", os.ErrProcessDone
		}
		return "", nil
	}
}

func fakeDockerRunner(runningContainerNames string) tmux.Runner {
	return func(args ...string) (string, error) {
		return runningContainerNames, nil
	}
}

func TestReadProjects_FromSessions(t *testing.T) {
	tmuxRunner := fakeTmuxRunner(
		"cws-focusreader\ncws-payments-api",
		map[string]string{
			"cws-focusreader":  "0 main:host-1\n1 main:clode-1",
			"cws-payments-api": "0 main:host-1",
		},
	)

	dir := t.TempDir()
	r := state.NewReader(dir, tmux.NewClient(tmuxRunner), fakeDockerRunner(""))
	st, err := r.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(st.Projects) != 2 {
		t.Fatalf("want 2 projects, got %d", len(st.Projects))
	}

	fr := st.Projects[0]
	if fr.Name != "focusreader" {
		t.Errorf("want focusreader first (sessions first), got %s", fr.Name)
	}
	if !fr.HasSession {
		t.Error("focusreader should have a session")
	}
	if len(fr.Worktrees) != 1 || fr.Worktrees[0].Slug != "main" {
		t.Errorf("want 1 worktree 'main', got: %+v", fr.Worktrees)
	}
	if len(fr.Worktrees[0].Terminals) != 2 {
		t.Errorf("want 2 terminals, got %d", len(fr.Worktrees[0].Terminals))
	}
	t0, t1 := fr.Worktrees[0].Terminals[0], fr.Worktrees[0].Terminals[1]
	if t0.Type != state.TypeHost {
		t.Errorf("terminal 0 should be TypeHost")
	}
	if t1.Type != state.TypeClode {
		t.Errorf("terminal 1 should be TypeClode")
	}
}

func TestReadProjects_DiskOnly(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"myapp", "otherapp"} {
		if err := os.MkdirAll(filepath.Join(dir, name, ".git"), 0755); err != nil {
			t.Fatal(err)
		}
	}

	tmuxRunner := fakeTmuxRunner("", nil)
	r := state.NewReader(dir, tmux.NewClient(tmuxRunner), fakeDockerRunner(""))
	st, err := r.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(st.Projects) != 2 {
		t.Fatalf("want 2 disk projects, got %d", len(st.Projects))
	}
	for _, p := range st.Projects {
		if p.HasSession {
			t.Errorf("disk-only project %s should not have a session", p.Name)
		}
		if p.Dir == "" {
			t.Errorf("disk-only project %s should have Dir set", p.Name)
		}
	}
}

func TestDetectedDetachedTerminal(t *testing.T) {
	tmuxRunner := fakeTmuxRunner(
		"cws-focusreader",
		map[string]string{
			"cws-focusreader": "0 main:host-1",
		},
	)
	dockerRunner := fakeDockerRunner("cws-focusreader-main")

	dir := t.TempDir()
	r := state.NewReader(dir, tmux.NewClient(tmuxRunner), dockerRunner)
	st, err := r.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(st.Projects) == 0 {
		t.Fatal("no projects returned")
	}
	wt := st.Projects[0].Worktrees[0]

	var detached *state.Terminal
	for i := range wt.Terminals {
		if wt.Terminals[i].Status == state.StatusDetached {
			detached = &wt.Terminals[i]
		}
	}
	if detached == nil {
		t.Errorf("expected a detached clode terminal; got terminals: %+v", wt.Terminals)
	}
	if detached.Type != state.TypeClode {
		t.Errorf("detached terminal should be TypeClode")
	}
	if detached.WindowIndex != -1 {
		t.Errorf("detached terminal should have WindowIndex=-1, got %d", detached.WindowIndex)
	}
	if detached.Container != "cws-focusreader-main" {
		t.Errorf("detached terminal Container wrong: %q", detached.Container)
	}
}

func TestContainerNameConvention(t *testing.T) {
	cases := []struct {
		project, slug, want string
	}{
		{"focusreader", "main", "cws-focusreader-main"},
		{"payments-api", "feature-auth", "cws-payments-api-feature-auth"},
	}
	for _, tc := range cases {
		got := state.ContainerName(tc.project, tc.slug)
		if got != tc.want {
			t.Errorf("ContainerName(%q, %q) = %q, want %q", tc.project, tc.slug, got, tc.want)
		}
	}
}

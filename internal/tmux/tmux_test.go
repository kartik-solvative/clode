package tmux_test

import (
	"fmt"
	"strings"
	"testing"

	"cws-tui/internal/tmux"
)

// captureRunner records the last call's args and returns canned output.
type captureRunner struct {
	out      string
	lastArgs []string
}

func (c *captureRunner) run(args ...string) (string, error) {
	c.lastArgs = args
	return c.out, nil
}

func fakeRunner(out string) tmux.Runner {
	return func(args ...string) (string, error) { return out, nil }
}

func TestListSessions(t *testing.T) {
	client := tmux.NewClient(fakeRunner("cws-focusreader\ncws-payments-api"))
	sessions, err := client.ListSessions()
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(sessions))
	}
	if sessions[0] != "cws-focusreader" {
		t.Errorf("want cws-focusreader, got %s", sessions[0])
	}
}

func TestListSessions_Empty(t *testing.T) {
	client := tmux.NewClient(func(args ...string) (string, error) { return "", nil })
	sessions, err := client.ListSessions()
	if err != nil {
		t.Fatalf("want nil error for empty sessions, got: %v", err)
	}
	if len(sessions) != 0 {
		t.Errorf("want 0 sessions, got %d", len(sessions))
	}
}

func TestListWindows(t *testing.T) {
	cr := &captureRunner{out: "0 main:host-1\n1 main:clode-1\n2 feature-auth:host-1"}
	client := tmux.NewClient(cr.run)
	windows, err := client.ListWindows("cws-focusreader")
	if err != nil {
		t.Fatal(err)
	}
	if len(windows) != 3 {
		t.Fatalf("want 3 windows, got %d", len(windows))
	}
	if windows[0].Index != 0 || windows[0].Name != "main:host-1" {
		t.Errorf("unexpected window[0]: %+v", windows[0])
	}
	if cr.lastArgs[2] != "cws-focusreader" {
		t.Errorf("want -t cws-focusreader in args, got: %v", cr.lastArgs)
	}
}

func TestCapturePane_ContentAndTarget(t *testing.T) {
	cr := &captureRunner{out: "$ claude --help\nClaude Code v1.0.3\n"}
	client := tmux.NewClient(cr.run)
	result, err := client.CapturePane("cws-focusreader", 3)
	if err != nil {
		t.Fatal(err)
	}
	if result != cr.out {
		t.Errorf("unexpected capture output: %q", result)
	}
	target := cr.lastArgs[2]
	if target != "cws-focusreader:3" {
		t.Errorf("want target cws-focusreader:3, got %q", target)
	}
	args := strings.Join(cr.lastArgs, " ")
	if !strings.Contains(args, "-S") || !strings.Contains(args, "-50") {
		t.Errorf("want -S -50 in capture-pane args, got: %v", cr.lastArgs)
	}
}

func TestSwitchClient(t *testing.T) {
	cr := &captureRunner{}
	client := tmux.NewClient(cr.run)
	err := client.SwitchClient("cws-focusreader:2")
	if err != nil {
		t.Fatal(err)
	}
	if cr.lastArgs[0] != "switch-client" {
		t.Errorf("want switch-client subcommand, got %v", cr.lastArgs)
	}
	if cr.lastArgs[2] != "cws-focusreader:2" {
		t.Errorf("want -t cws-focusreader:2, got %v", cr.lastArgs)
	}
}

func TestDetachClient(t *testing.T) {
	cr := &captureRunner{}
	client := tmux.NewClient(cr.run)
	if err := client.DetachClient(); err != nil {
		t.Fatal(err)
	}
	if cr.lastArgs[0] != "detach-client" {
		t.Errorf("want detach-client subcommand, got %v", cr.lastArgs)
	}
}

func TestNewSession(t *testing.T) {
	cr := &captureRunner{}
	client := tmux.NewClient(cr.run)
	err := client.NewSession("cws-focusreader", "/home/user/Projects/focusreader", "main:host-1")
	if err != nil {
		t.Fatal(err)
	}
	args := cr.lastArgs
	if args[0] != "new-session" {
		t.Errorf("want new-session, got %v", args)
	}
	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "-d") {
		t.Error("want -d flag (detached)")
	}
	if !strings.Contains(joined, "cws-focusreader") {
		t.Error("want session name in args")
	}
	if !strings.Contains(joined, "main:host-1") {
		t.Error("want window name in args")
	}
}

func TestHasSession_True(t *testing.T) {
	client := tmux.NewClient(fakeRunner(""))
	if !client.HasSession("cws-focusreader") {
		t.Error("want HasSession=true when runner returns no error")
	}
}

func TestHasSession_False(t *testing.T) {
	client := tmux.NewClient(func(args ...string) (string, error) {
		return "", fmt.Errorf("exit status 1")
	})
	if client.HasSession("cws-missing") {
		t.Error("want HasSession=false when runner returns error")
	}
}

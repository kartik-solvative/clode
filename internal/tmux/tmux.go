package tmux

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// Runner executes tmux subcommand args and returns stdout.
type Runner func(args ...string) (string, error)

// RealRunner is the production Runner — calls real tmux binary.
// Uses exec.Command with separate args (no shell string construction).
func RealRunner(args ...string) (string, error) {
	out, err := exec.Command("tmux", args...).Output()
	return strings.TrimRight(string(out), "\n"), err
}

// Window is a tmux window entry.
type Window struct {
	Index int
	Name  string
}

// Client wraps tmux subcommands with an injectable Runner.
type Client struct {
	run Runner
}

// NewClient creates a Client using the given Runner.
func NewClient(run Runner) *Client {
	return &Client{run: run}
}

// ListSessions returns all tmux session names. Returns nil slice (not error)
// when no sessions exist (tmux exits 1 with empty output).
func (c *Client) ListSessions() ([]string, error) {
	out, err := c.run("list-sessions", "-F", "#{session_name}")
	if err != nil || out == "" {
		return nil, nil
	}
	return strings.Split(strings.TrimRight(out, "\n"), "\n"), nil
}

// ListWindows returns all windows in session, parsed from "index name" lines.
func (c *Client) ListWindows(session string) ([]Window, error) {
	out, err := c.run("list-windows", "-t", session, "-F", "#{window_index} #{window_name}")
	if err != nil || out == "" {
		return nil, err
	}
	var windows []Window
	for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) != 2 {
			continue
		}
		idx, err := strconv.Atoi(parts[0])
		if err != nil {
			continue
		}
		windows = append(windows, Window{Index: idx, Name: parts[1]})
	}
	return windows, nil
}

// CapturePane returns the last 50 lines of window at windowIndex.
// Uses numeric index to avoid ambiguity with ":" in window names.
func (c *Client) CapturePane(session string, windowIndex int) (string, error) {
	target := fmt.Sprintf("%s:%d", session, windowIndex)
	out, err := c.run("capture-pane", "-t", target, "-p", "-e", "-S", "-50")
	return out, err
}

// SwitchClient switches the tmux client to target (e.g. "session:index").
func (c *Client) SwitchClient(target string) error {
	_, err := c.run("switch-client", "-t", target)
	return err
}

// DetachClient detaches the current client (keeps session alive).
func (c *Client) DetachClient() error {
	_, err := c.run("detach-client")
	return err
}

// NewSession creates a detached tmux session.
func (c *Client) NewSession(name, startDir, windowName string) error {
	_, err := c.run("new-session", "-d", "-s", name, "-c", startDir, "-n", windowName)
	return err
}

// HasSession reports whether session name exists.
func (c *Client) HasSession(name string) bool {
	_, err := c.run("has-session", "-t", name)
	return err == nil
}

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"cws-tui/internal/state"
	"cws-tui/internal/tmux"
	"cws-tui/internal/ui"
)

func dockerRunner(args ...string) (string, error) {
	out, err := exec.Command("docker", args...).Output()
	return strings.TrimRight(string(out), "\n"), err
}

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "--help" || os.Args[1] == "-h") {
		fmt.Println("cws-tui — clode workspace TUI")
		fmt.Println("  CWS_SELECT_PROJECT=<name>   pre-select a project on startup")
		fmt.Println("  _CLODE_WS_ACTION_KEY=<key>  override Ctrl+A action key")
		os.Exit(0)
	}

	projectsDir := os.Getenv("HOME") + "/Projects"
	if d := os.Getenv("CWS_PROJECTS_DIR"); d != "" {
		projectsDir = d
	}

	tc := tmux.NewClient(tmux.RealRunner)
	reader := state.NewReader(projectsDir, tc, dockerRunner)

	st, err := reader.Read()
	if err != nil {
		fmt.Fprintf(os.Stderr, "cws-tui: failed to read state: %v\n", err)
		os.Exit(1)
	}

	m := ui.New(st).WithCapturer(tc.CapturePane)
	if project := os.Getenv("CWS_SELECT_PROJECT"); project != "" {
		m = m.WithPreselect(project)
	}

	p := tea.NewProgram(m, tea.WithAltScreen())

	// Background state poller — sends StateMsg every 2 seconds.
	go func() {
		for {
			time.Sleep(2 * time.Second)
			newSt, err := reader.Read()
			if err != nil {
				continue
			}
			p.Send(ui.StateMsg(newSt))
		}
	}()

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "cws-tui: %v\n", err)
		os.Exit(1)
	}
}

package state

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"cws-tui/internal/tmux"
)

// Status indicates whether a terminal is running, detached, or stopped.
type Status int

const (
	StatusRunning  Status = iota // tmux window exists
	StatusDetached               // tmux window gone, Docker container still running (clode only)
	StatusStopped                // no window, no container
)

// TerminalType distinguishes host shells from clode containers.
type TerminalType int

const (
	TypeHost  TerminalType = iota
	TypeClode
)

// Terminal represents one tmux window (host or clode).
type Terminal struct {
	Name        string
	Type        TerminalType
	Status      Status
	WindowIndex int    // -1 when window is gone
	Container   string // Docker container name (clode only)
}

// Worktree groups terminals that share a slug prefix.
type Worktree struct {
	Slug      string
	Terminals []Terminal
}

// Project represents one cws project (may or may not have an active tmux session).
type Project struct {
	Name       string
	Dir        string // absolute disk path; empty if not found on disk
	HasSession bool
	Worktrees  []Worktree
}

// State is the full workspace state at a point in time.
type State struct {
	Projects []Project
}

// Reader produces State from tmux + Docker.
type Reader struct {
	projectsDir  string
	tc           *tmux.Client
	dockerRunner tmux.Runner
}

// NewReader creates a Reader. projectsDir is scanned for disk-only git repos.
func NewReader(projectsDir string, tc *tmux.Client, dockerRunner tmux.Runner) *Reader {
	return &Reader{projectsDir: projectsDir, tc: tc, dockerRunner: dockerRunner}
}

// ContainerName returns the Docker container name for a clode terminal.
// Convention mirrors _cws_container_name in clode-ws.sh:
//
//	"cws-<project>-<slug>-clode"
func ContainerName(project, slug string) string {
	return fmt.Sprintf("cws-%s-%s-clode", project, slug)
}

// Read produces a fresh State snapshot.
func (r *Reader) Read() (*State, error) {
	// 1. Get running Docker container names.
	containers, err := r.runningContainers()
	if err != nil {
		containers = nil // Docker failure is non-fatal
	}
	containerSet := make(map[string]bool, len(containers))
	for _, c := range containers {
		containerSet[c] = true
	}

	// 2. Build projects from active cws-* sessions.
	sessions, err := r.tc.ListSessions()
	if err != nil {
		sessions = nil
	}
	seenNames := make(map[string]bool)
	var projects []Project

	for _, session := range sessions {
		if !strings.HasPrefix(session, "cws-") {
			continue
		}
		name := session[len("cws-"):]
		seenNames[name] = true

		windows, _ := r.tc.ListWindows(session)
		worktrees := buildWorktrees(name, windows, containerSet)

		projects = append(projects, Project{
			Name:       name,
			Dir:        r.projectDir(name),
			HasSession: true,
			Worktrees:  worktrees,
		})
	}
	// Sort session-backed projects by name.
	sort.Slice(projects, func(i, j int) bool { return projects[i].Name < projects[j].Name })

	// 3. Add disk-only git repos not already covered.
	diskProjects, _ := r.diskProjects()
	sort.Strings(diskProjects)
	for _, name := range diskProjects {
		if seenNames[name] {
			continue
		}
		projects = append(projects, Project{
			Name: name,
			Dir:  filepath.Join(r.projectsDir, name),
		})
	}

	return &State{Projects: projects}, nil
}

// buildWorktrees groups windows by slug and synthesises detached clode slots.
func buildWorktrees(project string, windows []tmux.Window, containers map[string]bool) []Worktree {
	bySlug := make(map[string][]Terminal)
	var slugOrder []string

	for _, w := range windows {
		// Window name format: "<slug>:<type>-<n>"
		parts := strings.SplitN(w.Name, ":", 2)
		if len(parts) != 2 {
			continue
		}
		slug, typePart := parts[0], parts[1]

		var tt TerminalType
		if strings.HasPrefix(typePart, "clode") {
			tt = TypeClode
		} else {
			tt = TypeHost
		}

		if _, seen := bySlug[slug]; !seen {
			slugOrder = append(slugOrder, slug)
		}
		bySlug[slug] = append(bySlug[slug], Terminal{
			Name:        typePart,
			Type:        tt,
			Status:      StatusRunning,
			WindowIndex: w.Index,
			Container:   ContainerName(project, slug),
		})
	}

	// For each slug, check if a clode container is running without a tmux window.
	for slug := range bySlug {
		cname := ContainerName(project, slug)
		hasClodeWindow := false
		for _, t := range bySlug[slug] {
			if t.Type == TypeClode {
				hasClodeWindow = true
				break
			}
		}
		if !hasClodeWindow && containers[cname] {
			if _, seen := bySlug[slug]; !seen {
				slugOrder = append(slugOrder, slug)
			}
			bySlug[slug] = append(bySlug[slug], Terminal{
				Name:        "clode-1",
				Type:        TypeClode,
				Status:      StatusDetached,
				WindowIndex: -1,
				Container:   cname,
			})
		}
	}

	// Also check containers for slugs not seen in any window.
	// (A session exists but all windows for a slug were closed.)
	// We need to scan containers for this project to find orphaned slugs.
	prefix := fmt.Sprintf("cws-%s-", project)
	suffix := "-clode"
	for cname := range containers {
		if !strings.HasPrefix(cname, prefix) || !strings.HasSuffix(cname, suffix) {
			continue
		}
		inner := cname[len(prefix) : len(cname)-len(suffix)]
		slug := inner
		if _, seen := bySlug[slug]; !seen {
			slugOrder = append(slugOrder, slug)
			bySlug[slug] = append(bySlug[slug], Terminal{
				Name:        "clode-1",
				Type:        TypeClode,
				Status:      StatusDetached,
				WindowIndex: -1,
				Container:   cname,
			})
		}
	}

	var result []Worktree
	for _, slug := range slugOrder {
		result = append(result, Worktree{Slug: slug, Terminals: bySlug[slug]})
	}
	return result
}

// runningContainers returns Docker container names from `docker ps`.
func (r *Reader) runningContainers() ([]string, error) {
	out, err := r.dockerRunner("ps", "--format", "{{.Names}}")
	if err != nil || out == "" {
		return nil, err
	}
	var names []string
	for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if line != "" {
			names = append(names, line)
		}
	}
	return names, nil
}

// diskProjects returns names of directories under projectsDir that contain .git.
func (r *Reader) diskProjects() ([]string, error) {
	entries, err := os.ReadDir(r.projectsDir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		gitPath := filepath.Join(r.projectsDir, e.Name(), ".git")
		if _, err := os.Stat(gitPath); err == nil {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

// projectDir returns the absolute path to project on disk, or "".
func (r *Reader) projectDir(name string) string {
	p := filepath.Join(r.projectsDir, name)
	if _, err := os.Stat(p); err == nil {
		return p
	}
	return ""
}

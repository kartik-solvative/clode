#!/usr/bin/env bats

# Load the functions under test (source-only, no side effects)
setup() {
  # Source only the helper functions, not the main entry point
  source "$BATS_TEST_DIRNAME/../clode-ws.sh" 2>/dev/null || true
}

#!/usr/bin/env bats

# Load the functions under test (source-only, no side effects)
setup() {
  # Source only the helper functions, not the main entry point
  source "$BATS_TEST_DIRNAME/../clode-ws.sh" 2>/dev/null || true
}

@test "_cws_slugify: strips .worktrees/ prefix" {
  result="$(_cws_slugify ".worktrees/feature-auth")"
  [ "$result" = "feature-auth" ]
}

@test "_cws_slugify: replaces / with -" {
  result="$(_cws_slugify "feature/auth")"
  [ "$result" = "feature-auth" ]
}

@test "_cws_slugify: replaces whitespace with -" {
  result="$(_cws_slugify "my feature")"
  [ "$result" = "my-feature" ]
}

@test "_cws_slugify: main passes through unchanged" {
  result="$(_cws_slugify "main")"
  [ "$result" = "main" ]
}

@test "_cws_slugify: nested path in .worktrees/" {
  result="$(_cws_slugify ".worktrees/fix/issue-42")"
  [ "$result" = "fix-issue-42" ]
}

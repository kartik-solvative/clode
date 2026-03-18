#!/bin/sh

# Add the current UID to /etc/passwd if missing — needed by SSH, git, and other
# tools that call getpwuid(). Occurs when the container is run with -u <host-uid>.
if ! getent passwd "$(id -u)" > /dev/null 2>&1; then
  # Strip newlines/colons from HOME to prevent passwd field injection
  _safe_home=$(printf '%s' "$HOME" | tr -d '\n:')
  echo "user:x:$(id -u):$(id -g):host-user:${_safe_home}:/bin/sh" >> /etc/passwd
fi

# Write OAuth credentials to wherever HOME points
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  mkdir -p "$HOME/.claude"
  # Use printf %s to avoid shell expansion of token value (backticks, $(...), etc)
  printf '{"claudeAiOauth":{"oauth_token":"%s","expires_at":null,"refresh_token":null,"scopes":["user:inference","user:profile"]}}\n' \
    "$CLAUDE_CODE_OAUTH_TOKEN" > "$HOME/.claude/.credentials.json"
  chmod 600 "$HOME/.claude/.credentials.json"
fi

exec claude "$@"

#!/bin/sh

# Add the current UID to /etc/passwd if missing — needed by SSH, git, and other
# tools that call getpwuid(). Occurs when the container is run with -u <host-uid>.
if ! getent passwd "$(id -u)" > /dev/null 2>&1; then
  echo "user:x:$(id -u):$(id -g):host-user:${HOME}:/bin/sh" >> /etc/passwd
fi

# Write OAuth credentials to wherever HOME points
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/.credentials.json" << EOF
{"claudeAiOauth":{"oauth_token":"$CLAUDE_CODE_OAUTH_TOKEN","expires_at":null,"refresh_token":null,"scopes":["user:inference","user:profile"]}}
EOF
fi

exec claude "$@"

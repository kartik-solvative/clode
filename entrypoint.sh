#!/bin/sh

# Write OAuth credentials to wherever HOME points
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/.credentials.json" << EOF
{"claudeAiOauth":{"oauth_token":"$CLAUDE_CODE_OAUTH_TOKEN","expires_at":null,"refresh_token":null,"scopes":["user:inference","user:profile"]}}
EOF
fi

exec claude "$@"

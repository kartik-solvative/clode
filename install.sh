#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_RC="${HOME}/.zshrc"
SOURCE_LINE="source \"${REPO_DIR}/clode.sh\""

# Check dependencies
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed or not in PATH." >&2
  echo "Install Docker Desktop: https://www.docker.com/products/docker-desktop/" >&2
  exit 1
fi

echo "==> Building Docker image..."
docker build -t claude-code:latest "$REPO_DIR"

echo "==> Wiring shell functions..."
if grep -qF "clode.sh" "$SHELL_RC" 2>/dev/null; then
  echo "    Already in ${SHELL_RC} — skipping"
else
  echo "" >> "$SHELL_RC"
  echo "# Claude Code in Docker (clode)" >> "$SHELL_RC"
  echo "$SOURCE_LINE" >> "$SHELL_RC"
  echo "    Added to ${SHELL_RC}"
fi

echo ""
echo "Done! Run: source ~/.zshrc"
echo ""
echo "Required: export CLAUDE_CODE_OAUTH_TOKEN=<your-token>"
echo "Then try: clode --help"

FROM node:20-slim

# Install system dependencies + GitHub CLI
RUN apt-get update && apt-get install -y \
    git openssh-client bash curl python3 dumb-init \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Playwright's Chromium browser and all its system deps.
# PLAYWRIGHT_BROWSERS_PATH=/ms-playwright makes it available to all users
# and all projects inside the container (no per-project re-download needed).
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
# --no-sandbox is required because Docker drops kernel capabilities Chrome's
# sandbox needs. DISABLE_DEV_SHM avoids crashes on low /dev/shm allocations.
ENV PLAYWRIGHT_CHROMIUM_LAUNCH_ARGS="--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage"
RUN npx --yes playwright@latest install --with-deps chromium \
    && chmod -R a+rx /ms-playwright

# Create a non-root user for safer execution
RUN useradd -m -u 1001 claude

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default workdir — overridden at runtime by clode's -w flag to the actual project path.
# This ensures Claude Code session history is keyed by the same path on host and in Docker.
WORKDIR /workspace

# Default to non-root user, but allow override via -u flag
USER claude

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]

# Pass HOST_HOME so entrypoint knows where to write credentials when UID is overridden
ENV HOME=/home/claude

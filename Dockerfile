FROM node:20-slim

# Install git and openssh (needed for plugin marketplace cloning)
RUN apt-get update && apt-get install -y \
    git openssh-client bash curl python3 dumb-init \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for safer execution
RUN useradd -m -u 1001 claude

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the working directory
WORKDIR /workspace

# Default to non-root user, but allow override via -u flag
USER claude

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]

# Pass HOST_HOME so entrypoint knows where to write credentials when UID is overridden
ENV HOME=/home/claude

#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive

# --- Tailscale (account B) ---
command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1
tailscale up --authkey "${TS_AUTHKEY}" --hostname=workspace --accept-dns=false 2>&1 | tail -2
echo "ts-ip: $(tailscale ip -4 2>/dev/null)"

# --- Node.js 22 (runtime for the AI CLIs) ---
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null 2>&1
fi
echo "node: $(node -v 2>/dev/null) npm: $(npm -v 2>/dev/null)"

# --- AI CLIs (system-wide; each user logs into their own account) ---
npm install -g @anthropic-ai/claude-code @google/gemini-cli @openai/codex >/dev/null 2>&1 || \
  npm install -g @anthropic-ai/claude-code @google/gemini-cli @openai/codex 2>&1 | tail -4
echo "claude: $(claude --version 2>/dev/null || echo MISSING)"
echo "gemini: $(gemini --version 2>/dev/null || echo MISSING)"
echo "codex:  $(codex --version 2>/dev/null || echo MISSING)"

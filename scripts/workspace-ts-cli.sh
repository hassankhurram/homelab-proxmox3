#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive

# --- Tailscale (account B) ---
command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1
tailscale up --authkey "${TS_AUTHKEY}" --hostname=workspace --accept-dns=false 2>&1 | tail -2
echo "ts-ip: $(tailscale ip -4 2>/dev/null)"

# --- Per-user toolchain: nvm + native Claude (no system-wide Node) ---
# Each user manages their own Node via nvm and logs into their own AI accounts.
# Gemini/Codex are Node-based: after `nvm install --lts`, `npm i -g @google/gemini-cli @openai/codex`.
for u in shared harris hassan; do
  id "$u" >/dev/null 2>&1 || continue
  su - "$u" -c 'wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash' >/dev/null 2>&1
  su - "$u" -c 'curl -fsSL https://claude.ai/install.sh | bash' >/dev/null 2>&1
  echo "$u: nvm=$([ -s /home/$u/.nvm/nvm.sh ] && echo ok || echo no) claude=$([ -x /home/$u/.local/bin/claude ] && echo ok || echo no)"
done

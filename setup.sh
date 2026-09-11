#!/usr/bin/env bash
# setup.sh - First-time setup for memclaw-cross-fleet-gov (macOS / Linux)
# Run once from the repo root: bash setup.sh
# After this completes, day-to-day use is just: openclaw gateway restart

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="$HOME/.openclaw"
AGENTS=("sales-agent" "legal-agent" "admin-agent")
FLEETS=("fleet-org-shared" "fleet-sales" "fleet-legal")
MEMCLAW_URL="http://localhost:8000"

step()  { echo; echo ">> $1"; }
ok()    { echo "   OK: $1"; }
warn()  { echo "   WARN: $1"; }

echo
echo "MemClaw Cross-Fleet Gov - Setup"
echo "Repo: $REPO"

# ── 1. Prerequisites ──────────────────────────────────────────────────────────

step "Checking prerequisites"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not found. Install Docker and try again." >&2; exit 1
fi
ok "Docker found"

if ! command -v openclaw &>/dev/null; then
    echo "ERROR: OpenClaw not found. Run: npm install -g openclaw@latest" >&2; exit 1
fi
ok "OpenClaw found: $(openclaw --version 2>/dev/null || echo 'unknown')"

# ── 2. .env ───────────────────────────────────────────────────────────────────

step "Environment file"

if [ ! -f "$REPO/.env" ]; then
    cp "$REPO/.env.example" "$REPO/.env"
    warn ".env created from .env.example - open it and fill in LLM_GATEWAY_API_KEY and LLM_GATEWAY_BASE_URL before starting the gateway"
else
    ok ".env already exists"
fi

# ── 3. MemClaw Docker ─────────────────────────────────────────────────────────

step "Starting MemClaw (docker compose)"

MEMCLAW_DIR="$HOME/caura-memclaw"

if docker compose -f "$MEMCLAW_DIR/docker-compose.yml" ps --services --filter "status=running" 2>/dev/null | grep -q .; then
    ok "MemClaw already running"
else
    if [ ! -d "$MEMCLAW_DIR" ]; then
        echo "   Cloning caura-memclaw..."
        git clone https://github.com/caura-ai/caura-memclaw "$MEMCLAW_DIR"
    fi
    if [ ! -f "$MEMCLAW_DIR/.env" ]; then
        cp "$MEMCLAW_DIR/.env.example" "$MEMCLAW_DIR/.env"
        warn "MemClaw .env created at $MEMCLAW_DIR/.env - review it before first use"
    fi
    docker compose -f "$MEMCLAW_DIR/docker-compose.yml" up -d
    ok "MemClaw started"
fi

echo -n "   Waiting for MemClaw to be ready"
attempts=0
until curl -sf "$MEMCLAW_URL/api/v1/health" >/dev/null 2>&1; do
    sleep 2
    attempts=$((attempts + 1))
    echo -n "."
    if [ $attempts -ge 20 ]; then
        echo
        echo "ERROR: MemClaw did not become ready after 40s. Check: docker compose -f $MEMCLAW_DIR/docker-compose.yml logs" >&2
        exit 1
    fi
done
echo
ok "MemClaw is ready at $MEMCLAW_URL"

# ── 4. Agent workspace symlinks ───────────────────────────────────────────────

step "Creating workspace symlinks in ~/.openclaw"

mkdir -p "$OPENCLAW_HOME"

for agent in "${AGENTS[@]}"; do
    link="$OPENCLAW_HOME/workspace-$agent"
    target="$REPO/agents/$agent"

    if [ ! -d "$target" ]; then
        echo "ERROR: Agent directory not found: $target" >&2; exit 1
    fi

    if [ -L "$link" ]; then
        existing=$(readlink "$link")
        if [ "$existing" != "$target" ]; then
            rm "$link"
            ln -s "$target" "$link"
            ok "Symlink recreated: workspace-$agent -> $target"
        else
            ok "Symlink already correct: workspace-$agent"
        fi
    elif [ -d "$link" ]; then
        warn "$link exists as a real directory - skipping. Remove it manually if you want a symlink."
    else
        ln -s "$target" "$link"
        ok "Symlink created: workspace-$agent"
    fi
done

# ── 5. Governance skill ───────────────────────────────────────────────────────

step "Copying governance skill into agent workspaces"

for agent in "${AGENTS[@]}"; do
    skill_dir="$REPO/agents/$agent/skills"
    mkdir -p "$skill_dir"
    cp "$REPO/skills/memclaw-governance.md" "$skill_dir/memclaw-governance.md"
    ok "Skill copied to agents/$agent/skills/"
done

# ── 6. Register agents ────────────────────────────────────────────────────────

step "Registering agents with OpenClaw"

for agent in "${AGENTS[@]}"; do
    workspace="$OPENCLAW_HOME/workspace-$agent"
    if openclaw agents add "$agent" --workspace "$workspace" --non-interactive 2>/dev/null; then
        ok "Registered: $agent"
    else
        warn "$agent may already be registered (run 'openclaw agents list' to confirm)"
    fi
done

# ── 7. Install MemClaw plugin ─────────────────────────────────────────────────

step "Installing MemClaw plugin"

for fleet in "${FLEETS[@]}"; do
    url="$MEMCLAW_URL/api/v1/install-plugin?fleet_id=$fleet&api_url=$MEMCLAW_URL"
    tmp_script="$(mktemp /tmp/memclaw-plugin-${fleet}-XXXXXX.sh 2>/dev/null || mktemp -t memclaw-plugin-${fleet}-XXXXXX.sh)"
    if curl -sf "$url" -o "$tmp_script"; then
        echo "  Saved plugin installer to $tmp_script for inspection"
        if bash "$tmp_script"; then
            ok "Plugin installed for $fleet"
        else
            warn "Plugin install for $fleet failed or already installed"
        fi
        rm -f "$tmp_script"
    else
        warn "Plugin download for $fleet failed"
    fi
done

# ── 8. Start gateway ──────────────────────────────────────────────────────────

step "Starting OpenClaw gateway"

openclaw gateway restart
sleep 3

step "Verifying agent bindings"
openclaw agents list --bindings

# ── Done ──────────────────────────────────────────────────────────────────────

echo
echo "Setup complete."
echo
echo "Next steps:"
echo "  1. Open .env and set LLM_GATEWAY_API_KEY and LLM_GATEWAY_BASE_URL"
echo "     -- for Ollama: LLM_GATEWAY_API_KEY=ollama, LLM_GATEWAY_BASE_URL=http://localhost:11434/v1, LLM_GATEWAY_MODEL=qwen2.5:14b"
echo "  2. Run: openclaw gateway restart   (after saving .env)"
echo "  3. Run: openclaw dashboard         (opens http://127.0.0.1:18789)"
echo "  4. Follow the Governance Validation steps in README.md"
echo
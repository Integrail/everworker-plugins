#!/usr/bin/env bash
# SessionStart hook: verifies the configured Everworker instance is reachable,
# the JWT works, and the server's MCP contract version matches what this plugin
# expects. All output is non-fatal — warnings go to stderr, plugin still loads.

set -uo pipefail

URL="${CLAUDE_PLUGIN_OPTION_EVERWORKER_URL:-}"
JWT="${CLAUDE_PLUGIN_OPTION_EVERWORKER_JWT:-}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

if [ -z "$URL" ] || [ -z "$JWT" ]; then
    echo "[ai-builder] WARN: everworker_url or everworker_jwt is not configured. Run /plugin to set them." >&2
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[ai-builder] WARN: jq is not installed; skipping server-contract check. Install with: brew install jq" >&2
    exit 0
fi

URL="${URL%/}"
RESPONSE=$(curl -fsS -m 5 -H "Authorization: Bearer $JWT" "$URL/api/v1/agents/health" 2>&1) || {
    echo "[ai-builder] WARN: cannot reach $URL/api/v1/agents/health — $RESPONSE" >&2
    exit 0
}

SERVER_CONTRACT=$(echo "$RESPONSE" | jq -r '.data.pluginContract // empty' 2>/dev/null)
SERVER_FEATURES=$(echo "$RESPONSE" | jq -r '.data.supportedFeatures // [] | join(",")' 2>/dev/null)

if [ -z "$SERVER_CONTRACT" ]; then
    echo "[ai-builder] WARN: server did not report a pluginContract. It is likely older than 0.7.0 — some deploys may fail with cryptic MCP errors." >&2
    exit 0
fi

MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
if [ ! -r "$MANIFEST" ]; then
    exit 0
fi

PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$MANIFEST")
MIN_CONTRACT=$(jq -r '."x-everworker".minServerContract // empty' "$MANIFEST")
REQUIRED_FEATURES=$(jq -r '."x-everworker".requiredFeatures // [] | join(",")' "$MANIFEST")

# Compare semver-ish "X.Y.Z" strings. Returns 0 if $1 >= $2, 1 otherwise.
semver_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

if [ -n "$MIN_CONTRACT" ]; then
    if ! semver_ge "$SERVER_CONTRACT" "$MIN_CONTRACT"; then
        echo "[ai-builder] WARN: Everworker server contract is $SERVER_CONTRACT; this plugin (ai-builder $PLUGIN_VERSION) requires $MIN_CONTRACT+. Some deploys will fail. Either upgrade Everworker, or install a matching ai-builder channel from the marketplace." >&2
    elif ! semver_ge "$MIN_CONTRACT" "$SERVER_CONTRACT" && [ "$SERVER_CONTRACT" != "$MIN_CONTRACT" ]; then
        echo "[ai-builder] INFO: Server contract is $SERVER_CONTRACT; this plugin is $PLUGIN_VERSION. Some newer features may be missing. Run /plugin marketplace update everworker to refresh." >&2
    fi
fi

if [ -n "$REQUIRED_FEATURES" ]; then
    MISSING=""
    IFS=',' read -ra REQ <<< "$REQUIRED_FEATURES"
    for feature in "${REQ[@]}"; do
        if ! echo ",$SERVER_FEATURES," | grep -q ",$feature,"; then
            MISSING="${MISSING:+$MISSING, }$feature"
        fi
    done
    if [ -n "$MISSING" ]; then
        echo "[ai-builder] WARN: Server is missing required features: $MISSING. Operations that depend on them will fail." >&2
    fi
fi

# Inject runtime values directly into the LLM's session context via the
# SessionStart hook's `additionalContext` channel. Neither `${user_config.X}`
# nor `${CLAUDE_PLUGIN_ROOT}` is substituted inside skill / playbook markdown,
# so the only reliable way for the LLM to know the configured URL (and avoid
# hallucinating it into sidecars / final-report links) is to put it directly
# in the system context. No JWT is included — secrets never leak into LLM
# context.
FEATURES_LIST="${SERVER_FEATURES:-}"
ADDITIONAL_CONTEXT=$(printf '%s\n' \
    "[ai-builder runtime]" \
    "The configured Everworker instance for this session:" \
    "- everworker_url: $URL" \
    "- server contract version: ${SERVER_CONTRACT:-unknown}" \
    "- plugin version: $PLUGIN_VERSION" \
    "- server supported features: ${FEATURES_LIST:-(none reported)}" \
    "" \
    "Use the everworker_url above verbatim wherever the playbook or any SKILL.md shows the placeholder \${user_config.everworker_url} — that token is NOT substituted by Claude Code in markdown; substitute it yourself with the value above. Sidecar everworkerUrl fields and canvas / editor / chat links in final reports all use this URL. Never hallucinate a URL.")

jq -n --arg ctx "$ADDITIONAL_CONTEXT" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

# Also write a defensive-fallback runtime.json under the plugin root in case
# the LLM ever needs to re-read these values mid-session. The path is not
# stable across installs (depends on where Claude Code clones the plugin), so
# the primary delivery channel is the additionalContext above.
if [ -n "$PLUGIN_ROOT" ]; then
    RUNTIME_DIR="$PLUGIN_ROOT/runtime"
    if mkdir -p "$RUNTIME_DIR" 2>/dev/null; then
        WRITTEN_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        FEATURES_JSON=$(echo "$RESPONSE" | jq -c '.data.supportedFeatures // []' 2>/dev/null || echo '[]')
        cat > "$RUNTIME_DIR/runtime.json" <<EOF
{
  "everworkerUrl": "$URL",
  "serverContract": "${SERVER_CONTRACT:-unknown}",
  "supportedFeatures": $FEATURES_JSON,
  "pluginVersion": "$PLUGIN_VERSION",
  "writtenAt": "$WRITTEN_AT"
}
EOF
    fi
fi

exit 0

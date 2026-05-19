#!/usr/bin/env bash
# PreToolUse hook for the ai-builder plugin.
#
# Enforces the workflow-as-code discipline for both Workflows and Code Nodes:
# a deploy is only allowed when the corresponding local files exist and their
# canonical contents match the payload being deployed.
#
# For code-node updates, additionally enforces the "ask before editing
# remote-origin nodes" guardrail: if the local sidecar's createdInSession is
# false (i.e. cloned from the server, not authored in this session), the update
# is blocked unless the sidecar also has a `confirmedAt` timestamp newer than
# the modification times of <slug>.code.js and <slug>.code.schema.json.
#
# Reads the tool call JSON on stdin (Claude Code hook protocol).
# Emits a JSON decision on stdout. Exit 0 always — block decisions are conveyed
# in the JSON body.

set -uo pipefail

WORKFLOWS_DIR="./everworker-workflows"

block() {
    local reason="$1"
    jq -n --arg r "$reason" '{decision: "block", reason: $r}'
    exit 0
}

allow() {
    exit 0
}

# jq is required.
if ! command -v jq >/dev/null 2>&1; then
    echo "[ai-builder] WARN: jq not found in PATH; skipping local-copy guard." >&2
    allow
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
ARGS=$(echo "$INPUT" | jq -c '.tool_input // {}')

slugify() {
    # kebab-case ASCII slug
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# mtime in seconds (cross-platform: try GNU stat, fall back to BSD stat).
mtime_secs() {
    local f="$1"
    [ -f "$f" ] || { echo 0; return; }
    if stat -c '%Y' "$f" >/dev/null 2>&1; then
        stat -c '%Y' "$f"
    else
        stat -f '%m' "$f" 2>/dev/null || echo 0
    fi
}

# Convert ISO-8601 to epoch seconds (best effort: GNU date, then BSD date).
iso_to_epoch() {
    local iso="$1"
    [ -z "$iso" ] && { echo 0; return; }
    if date -d "$iso" +%s >/dev/null 2>&1; then
        date -d "$iso" +%s
    else
        # BSD: try parsing common ISO formats
        date -j -u -f "%Y-%m-%dT%H:%M:%S" "${iso%%.*}" +%s 2>/dev/null \
            || date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${iso%%.*}Z" +%s 2>/dev/null \
            || echo 0
    fi
}

case "$TOOL_NAME" in
    mcp__ai_builder__workflow_create)
        WJ=$(echo "$ARGS" | jq -c '.workflowJson // empty')
        if [ -z "$WJ" ]; then
            # Empty-stub create (name only) — nothing to compare against. Allow.
            allow
        fi

        NAME=$(echo "$WJ" | jq -r '.name // ""')
        if [ -z "$NAME" ]; then
            block "workflow_create: workflowJson must include a 'name' field."
        fi

        SLUG=$(slugify "$NAME")
        FILE="$WORKFLOWS_DIR/$SLUG.json"

        if [ ! -f "$FILE" ]; then
            block "Local copy missing: '$FILE' must exist before deploying this workflow. Use Write to save the exact workflowJson you intend to deploy, then retry workflow_create."
        fi

        LOCAL_CANON=$(jq -S '.' < "$FILE" 2>/dev/null) || \
            block "Local file '$FILE' is not valid JSON. Re-Write it with the workflowJson, then retry."
        DEPLOY_CANON=$(echo "$WJ" | jq -S '.')

        if [ "$LOCAL_CANON" != "$DEPLOY_CANON" ]; then
            block "Local file '$FILE' contents differ from the workflowJson being deployed. Re-Write the file with the exact JSON you intend to deploy (use canonical JSON), then retry."
        fi
        allow
        ;;

    mcp__ai_builder__workflow_update)
        WID=$(echo "$ARGS" | jq -r '.workflowId // ""')
        WJ=$(echo "$ARGS" | jq -c '.workflowJson // empty')

        if [ -z "$WID" ] || [ -z "$WJ" ]; then
            # Malformed call; let the tool surface its own error.
            allow
        fi

        if [ ! -d "$WORKFLOWS_DIR" ]; then
            block "No '$WORKFLOWS_DIR' directory in cwd. workflow_read the remote, Write the JSON to '$WORKFLOWS_DIR/<slug>.json' (and a sidecar '<slug>.meta.json' with workflowId), then retry workflow_update."
        fi

        # Locate sidecar whose workflowId matches.
        SIDECAR=""
        for meta in "$WORKFLOWS_DIR"/*.meta.json; do
            [ -e "$meta" ] || continue
            # Skip code-node sidecars
            case "$meta" in *.code.meta.json) continue ;; esac
            META_WID=$(jq -r '.workflowId // ""' < "$meta" 2>/dev/null || echo "")
            if [ "$META_WID" = "$WID" ]; then
                SIDECAR="$meta"
                break
            fi
        done

        if [ -z "$SIDECAR" ]; then
            block "No local sidecar in '$WORKFLOWS_DIR' references workflowId '$WID'. workflow_read the remote, Write the JSON locally and a sidecar with this workflowId, then retry workflow_update."
        fi

        BASE="${SIDECAR%.meta.json}"
        FILE="$BASE.json"

        if [ ! -f "$FILE" ]; then
            block "Sidecar '$SIDECAR' exists but workflow file '$FILE' is missing. Re-Write the workflow JSON to that file, then retry workflow_update."
        fi

        LOCAL_CANON=$(jq -S '.' < "$FILE" 2>/dev/null) || \
            block "Local file '$FILE' is not valid JSON. Re-Write it with the workflowJson, then retry."
        DEPLOY_CANON=$(echo "$WJ" | jq -S '.')

        if [ "$LOCAL_CANON" != "$DEPLOY_CANON" ]; then
            block "Local file '$FILE' contents differ from the workflowJson being deployed. Edit the file to the exact JSON you intend to deploy, then retry workflow_update."
        fi
        allow
        ;;

    mcp__ai_builder__custom_node_create)
        NAME=$(echo "$ARGS" | jq -r '.name // ""')
        if [ -z "$NAME" ]; then
            block "custom_node_create: 'name' is required."
        fi

        SLUG=$(slugify "$NAME")
        JS_FILE="$WORKFLOWS_DIR/$SLUG.code.js"
        SCHEMA_FILE="$WORKFLOWS_DIR/$SLUG.code.schema.json"

        if [ ! -f "$JS_FILE" ]; then
            block "Local copy missing: '$JS_FILE' must exist before deploying this code node. Write the JavaScript body to that file, then retry custom_node_create."
        fi
        if [ ! -f "$SCHEMA_FILE" ]; then
            block "Local copy missing: '$SCHEMA_FILE' must exist before deploying this code node. Write { name, description, inputSchema, outputSchema?, tags?, timeoutMs? } to that file, then retry."
        fi

        # Compare code body byte-for-byte.
        DEPLOY_CODE=$(echo "$ARGS" | jq -r '.code // ""')
        LOCAL_CODE=$(cat "$JS_FILE")
        if [ "$LOCAL_CODE" != "$DEPLOY_CODE" ]; then
            block "Code in '$JS_FILE' differs from the 'code' argument being deployed. Re-Write the file with the exact code you intend to deploy, then retry."
        fi

        # Compare schema fields. Local schema file is the source of truth for
        # name/description/inputSchema/outputSchema/tags. Hook canonicalises both
        # sides and compares.
        LOCAL_SCHEMA=$(jq -S '{name, description, inputSchema, outputSchema, tags}' < "$SCHEMA_FILE" 2>/dev/null) || \
            block "Local file '$SCHEMA_FILE' is not valid JSON. Re-Write it, then retry."
        DEPLOY_SCHEMA=$(echo "$ARGS" | jq -S '{name, description, inputSchema, outputSchema, tags}')

        if [ "$LOCAL_SCHEMA" != "$DEPLOY_SCHEMA" ]; then
            block "Schema fields in '$SCHEMA_FILE' differ from what's being deployed (name/description/inputSchema/outputSchema/tags). Update the file, then retry."
        fi
        allow
        ;;

    mcp__ai_builder__custom_node_update)
        CNID=$(echo "$ARGS" | jq -r '.codeNodeId // ""')
        if [ -z "$CNID" ]; then
            allow
        fi

        if [ ! -d "$WORKFLOWS_DIR" ]; then
            block "No '$WORKFLOWS_DIR' directory in cwd. custom_node_read the remote first, Write the JS body and schema sidecar locally and a '<slug>.code.meta.json' with this codeNodeId, then retry."
        fi

        # Locate the code-node sidecar whose codeNodeId matches.
        SIDECAR=""
        for meta in "$WORKFLOWS_DIR"/*.code.meta.json; do
            [ -e "$meta" ] || continue
            META_ID=$(jq -r '.codeNodeId // ""' < "$meta" 2>/dev/null || echo "")
            if [ "$META_ID" = "$CNID" ]; then
                SIDECAR="$meta"
                break
            fi
        done

        if [ -z "$SIDECAR" ]; then
            block "No local sidecar in '$WORKFLOWS_DIR' references codeNodeId '$CNID'. custom_node_read the remote, Write the JS body + schema sidecar locally and a '<slug>.code.meta.json' with this codeNodeId, then retry."
        fi

        BASE="${SIDECAR%.code.meta.json}"
        JS_FILE="$BASE.code.js"
        SCHEMA_FILE="$BASE.code.schema.json"

        if [ ! -f "$JS_FILE" ] || [ ! -f "$SCHEMA_FILE" ]; then
            block "Sidecar '$SIDECAR' exists but '$JS_FILE' and/or '$SCHEMA_FILE' is missing. Re-Write them, then retry."
        fi

        # Guardrail: editing a remote-origin code node requires explicit user
        # confirmation reflected in the sidecar's `confirmedAt` field.
        CREATED_IN_SESSION=$(jq -r '.createdInSession // false' < "$SIDECAR" 2>/dev/null || echo "false")
        if [ "$CREATED_IN_SESSION" != "true" ]; then
            CONFIRMED_AT=$(jq -r '.confirmedAt // ""' < "$SIDECAR" 2>/dev/null || echo "")
            CONFIRM_EPOCH=$(iso_to_epoch "$CONFIRMED_AT")
            JS_MTIME=$(mtime_secs "$JS_FILE")
            SCHEMA_MTIME=$(mtime_secs "$SCHEMA_FILE")
            NEWEST_MTIME=$JS_MTIME
            [ "$SCHEMA_MTIME" -gt "$NEWEST_MTIME" ] 2>/dev/null && NEWEST_MTIME=$SCHEMA_MTIME

            if [ "$CONFIRM_EPOCH" -le "$NEWEST_MTIME" ] 2>/dev/null; then
                block "Code node '$CNID' was not created in this session (sidecar.createdInSession is not true). Render the proposed change as a markdown diff, ask the user to confirm explicitly, then write \`confirmedAt\` (ISO-8601, AFTER any further file edits) into '$SIDECAR' before retrying custom_node_update."
            fi
        fi

        # Compare code body if 'code' is in the args.
        if echo "$ARGS" | jq -e 'has("code")' >/dev/null; then
            DEPLOY_CODE=$(echo "$ARGS" | jq -r '.code // ""')
            LOCAL_CODE=$(cat "$JS_FILE")
            if [ "$LOCAL_CODE" != "$DEPLOY_CODE" ]; then
                block "Code in '$JS_FILE' differs from the 'code' argument being deployed. Edit the file to match the exact code you intend to deploy, then retry."
            fi
        fi

        # Compare each schema field provided in the args against the local
        # schema file. Only fields actually in the call are checked.
        for field in name description inputSchema outputSchema tags; do
            if echo "$ARGS" | jq -e --arg k "$field" 'has($k)' >/dev/null; then
                DEPLOY_VAL=$(echo "$ARGS" | jq -cS --arg k "$field" '.[$k]')
                LOCAL_VAL=$(jq -cS --arg k "$field" '.[$k] // null' < "$SCHEMA_FILE" 2>/dev/null)
                if [ "$DEPLOY_VAL" != "$LOCAL_VAL" ]; then
                    block "Schema field '$field' in '$SCHEMA_FILE' differs from what's being deployed. Update the file, then retry."
                fi
            fi
        done
        allow
        ;;

    mcp__ai_builder__worker_create)
        NAME=$(echo "$ARGS" | jq -r '.name // ""')
        if [ -z "$NAME" ]; then
            block "worker_create: 'name' is required."
        fi

        SLUG=$(slugify "$NAME")
        FILE="$WORKFLOWS_DIR/$SLUG.worker.json"

        if [ ! -f "$FILE" ]; then
            block "Local copy missing: '$FILE' must exist before deploying this Universal Worker. Use Write to save the exact spec args you intend to deploy (everything except the implicit defaults), then retry worker_create."
        fi

        # Compare the deploy args (minus workerId) against the on-disk spec.
        LOCAL_CANON=$(jq -S '.' < "$FILE" 2>/dev/null) || \
            block "Local file '$FILE' is not valid JSON. Re-Write it with the spec args, then retry."
        DEPLOY_CANON=$(echo "$ARGS" | jq -S '.')

        if [ "$LOCAL_CANON" != "$DEPLOY_CANON" ]; then
            block "Local file '$FILE' contents differ from the worker spec being deployed. Re-Write the file with the exact args you intend to deploy (canonical JSON), then retry worker_create."
        fi
        allow
        ;;

    mcp__ai_builder__worker_update)
        WID=$(echo "$ARGS" | jq -r '.workerId // ""')
        if [ -z "$WID" ]; then
            allow
        fi

        if [ ! -d "$WORKFLOWS_DIR" ]; then
            block "No '$WORKFLOWS_DIR' directory in cwd. worker_read the remote, Write the spec to '$WORKFLOWS_DIR/<slug>.worker.json' (and a sidecar '<slug>.worker.meta.json' with workerId), then retry worker_update."
        fi

        # Locate sidecar whose workerId (or legacy workflowId) matches.
        SIDECAR=""
        for meta in "$WORKFLOWS_DIR"/*.worker.meta.json; do
            [ -e "$meta" ] || continue
            META_WID=$(jq -r '.workerId // .workflowId // ""' < "$meta" 2>/dev/null || echo "")
            if [ "$META_WID" = "$WID" ]; then
                SIDECAR="$meta"
                break
            fi
        done

        if [ -z "$SIDECAR" ]; then
            block "No local sidecar in '$WORKFLOWS_DIR' references workerId '$WID'. worker_read the remote, Write the spec locally and a sidecar with this workerId, then retry worker_update."
        fi

        BASE="${SIDECAR%.worker.meta.json}"
        FILE="$BASE.worker.json"

        if [ ! -f "$FILE" ]; then
            block "Sidecar '$SIDECAR' exists but spec file '$FILE' is missing. Re-Write the worker spec to that file, then retry worker_update."
        fi

        LOCAL_CANON=$(jq -S '.' < "$FILE" 2>/dev/null) || \
            block "Local file '$FILE' is not valid JSON. Re-Write it with the spec args, then retry."
        # Drop the workerId from the deploy args before comparing — the local spec doesn't store it.
        DEPLOY_CANON=$(echo "$ARGS" | jq -S 'del(.workerId)')

        if [ "$LOCAL_CANON" != "$DEPLOY_CANON" ]; then
            block "Local file '$FILE' contents differ from the worker spec being deployed. Edit the file to match the exact args (minus workerId) you intend to deploy, then retry worker_update."
        fi
        allow
        ;;

    *)
        allow
        ;;
esac

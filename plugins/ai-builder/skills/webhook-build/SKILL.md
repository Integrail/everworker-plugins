---
description: Plan, create, modify, and delete Everworker Webhooks — inbound HTTP triggers that fan out to one or more Workflows. Use when the user wants an external system (Slack, GitHub, Stripe, a custom client) to call into Everworker.
---

The user wants to work with an Everworker Webhook. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Scope this session to the playbook's **WEBHOOKS** and **DESTRUCTIVE-ACTION GUARDRAIL** sections.

Run a focused **Plan → Develop → Test** loop:

1. **Research** — list what already exists (`mcp__ai_builder__webhook_search`). If the user named a specific webhook, `_read` it first and surface a short summary (webhookId, target Workflow IDs, auth method, execution mode, call counts). Don't propose creating a duplicate.
2. **Identify the target Workflow(s)** — webhooks fan out to one or more **Workflows**, NOT Universal Workers (Universal Workers expect a chat-style userMessage/session and are not valid webhook targets). Use `mcp__ai_builder__workflow_search` to confirm each target Workflow exists and is owned by the user. If the user's request implies a Workflow that doesn't exist yet, **stop and hand off to `/ai-builder:build`** — this skill does not create Workflows. The stored field is legacy-named `workerIds`, but the IDs must reference Workflows.
3. **Plan inline** — render a short markdown plan: name, target Workflow IDs, auth method (with rationale for the choice), execution mode (`sync` vs `async`), custom header config if any. Wait for explicit user approval before creating anything.
4. **Create / update / delete** —
   - `mcp__ai_builder__webhook_create` returns the signing **secret exactly once**. Render it to the user verbatim in a fenced code block alongside the invocation URL, and tell them to store it now — it cannot be retrieved later (only rotated).
   - `mcp__ai_builder__webhook_update` for non-secret changes.
   - `mcp__ai_builder__webhook_regenerate_secret` rotates the secret — old callers will start failing auth immediately. Confirm before rotating.
   - `mcp__ai_builder__webhook_delete` is destructive — follow the playbook's destructive-action guardrail: summarise impact (which external callers will start receiving 404s), wait for explicit `confirm`, then act.
5. **Verify** — produce a ready-to-paste curl example using the returned URL + secret, in the auth method's expected header shape:
   - `secret_header`: `-H "X-Webhook-Secret: <secret>"`
   - `bearer_token`: `-H "Authorization: Bearer <secret>"`
   - `api_key`: `-H "X-API-Key: <secret>"`
   - `hmac_signature`: explain how to compute `X-Webhook-Signature: sha256=<hex>` over the request body
   - `custom_header`: use the configured header name and (optional) prefix
   - `slack_auth`: the signing secret is the Slack App Signing Secret — wire up via Slack's Events API, no curl needed
6. **Final report** — render a short markdown summary inline: webhook name, invocation URL, auth method, target Workflows, and a clickable link to the Everworker UI:
   `[<webhook name>](${user_config.everworker_url}/providers)`

Webhooks are **server-side** — no on-disk sidecar discipline, and the PreToolUse hook does not gate `webhook_*` calls. Safety lives in the secret-handling and destructive-action guardrails above.

**Solution tags:** Webhooks **do not support server-side tags** (no `tags` field on `IWebhook`). When the webhook is part of a multi-entity solution, record the `solutionTag` for cross-reference in any local notes you keep, but skip it on the server. See PLAYBOOK § SOLUTION TAGS for the full rule.

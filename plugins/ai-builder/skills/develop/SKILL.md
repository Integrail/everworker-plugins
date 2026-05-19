---
description: Develop an Everworker AI Workflow — create a new one or modify an existing one — without running the full Plan cycle. Use when the user already knows what they want, or has approved a previous plan.
---

The user wants to develop or modify a workflow. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Run **Develop only** (skip Plan, skip Test):

- If the request references an existing workflow (by ID or name), follow the playbook's **Update flow**: read remote → ensure local file exists → drift check → edit local → `workflow_update` → update sidecar.
- If the request is a new workflow, follow the **Create flow**: draft JSON → Write `./everworker-workflows/<slug>.json` → `workflow_create` → write sidecar.
- If the request is about a **code node** (a reusable JS block, not a workflow), hand off to `/ai-builder:code-node-build` — it scopes the session to the playbook's **Code Nodes** section and applies the "ask before editing remote-origin nodes" guardrail.
- If the request is about a **Universal Worker** (a conversational reasoning agent — chat assistant, Slack bot, open-ended agentic task), hand off to `/ai-builder:build-worker`. Workers use the dedicated factory tools (`worker_create` / `worker_update` — structured spec, no raw JSON) and have their own on-disk filenames (`<slug>.worker.json`). `workflow_create` / `workflow_update` will refuse worker payloads.
- If the workflow needs a **Memory or Collection that doesn't exist yet** (RAG ingestion, a new knowledge base, a typed data table), hand off to `/ai-builder:data-build` for the data-layer setup, then resume the workflow.
- **Apply the solution tag (if any) to every taggable entity created or modified — see PLAYBOOK § SOLUTION TAGS.** When opening an existing on-disk entity, read its sidecar `solutionTag` and reuse it; for new entities that lack a tag, ask whether they belong to an existing solution, a new one, or a one-off.
- Do not execute the workflow afterwards — testing is a separate skill (`/ai-builder:test`).
- Render a brief summary of what changed inline, with a clickable canvas link.

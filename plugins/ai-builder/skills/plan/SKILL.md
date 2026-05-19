---
description: Plan an Everworker AI Workflow as a solution architect would — translate the business outcome into the simplest, most elegant combination of platform features. Returns a markdown plan with a one-line arrow diagram and node breakdown for review.
---

The user wants a workflow plan. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Run **Plan only**. Approach this as a solution architect, not a feature spec writer:

- Start by restating the business outcome in one sentence in your own words. If you can't, ask one clarifying question first.
- Map requirements to the smallest, most elegant combination of platform features. **Combine features; don't multiply them.** Reuse before building. Don't enrich the requirements — no bonus inputs, no "while we're at it" features, no error-handling branches the user didn't ask for. Anything tempting goes in *Possible follow-ups*, not in the plan.
- Justify every node in one sentence. If you can't, it shouldn't be there.

Process:

- Call `mcp__ai_builder__providers_list` and `mcp__ai_builder__schema_get_nodes` only when you'll use them — never guess provider IDs or node `methodId`s.
- Call `mcp__ai_builder__workflow_search` and `mcp__ai_builder__custom_node_search` to find reusable parts. If the workflow will use RAG or a typed data store, also `mcp__ai_builder__memory_search` / `mcp__ai_builder__collection_search` — flag any missing data store as a prerequisite that `/ai-builder:data-build` should set up first.
- Render the plan inline as markdown, following the PLAYBOOK's **Design & Present** structure: Problem → Approach → Dependencies → Workflow shape (one-line arrow diagram using `→`, no mermaid) → Node breakdown table → **Solution tag** (if the plan produces more than one taggable entity, propose a `solution:<slug>` per § SOLUTION TAGS) → Possible follow-ups (optional) → Open questions (only if a real ambiguity blocks the build).
- **Do not call `mcp__ai_builder__workflow_create` or `workflow_update`.** Stop at plan presentation.
- If the user later approves, they will run `/ai-builder:develop` or `/ai-builder:build` to materialize it.

Provider connection state (`isConnected: false`) is not a blocker — API-key providers always show as disconnected. Don't gate planning on it.

If the user's intent is actually a **chat-style assistant, an interactive AI, a Slack-bot persona, or an open-ended agentic task** (reasoning agent + tool belt, not a deterministic pipeline), hand off to `/ai-builder:build-worker` instead — it's the dedicated Plan → Develop → Test flow for Universal Workers. Apply the playbook's "Universal Worker vs Workflow" decision rule when in doubt.

---
description: Plan, develop, and test an Everworker AI Workflow end-to-end from a natural-language request. Use this when the user wants to build a new workflow.
---

The user wants to build an Everworker workflow. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Run the **full Plan → Develop → Test cycle** as specified in the playbook:

1. **Plan like a solution architect.** Restate the business outcome in one sentence; map it to the smallest, most elegant combination of platform features. Combine features; don't multiply them. Don't enrich the requirements. Reuse before building. Justify every node in one sentence.
2. Research only what you'll use: providers, node types, custom nodes, existing workflows, memories/collections.
3. Render the plan inline following the PLAYBOOK's **Design & Present** structure: Problem → Approach → Dependencies → Workflow shape (one-line arrow diagram using `→`, **no mermaid**) → Node breakdown table → Possible follow-ups (optional) → Open questions (only if blocking).
4. **Wait for explicit user approval.** A clarification answer is not approval.
5. After approval, follow the workflow-as-code discipline: Write the JSON to `./everworker-workflows/<slug>.json`, then `mcp__ai_builder__workflow_create`, then write the sidecar.
6. **Apply the solution tag (if any) to every taggable entity created or modified — see PLAYBOOK § SOLUTION TAGS.** When opening an existing on-disk entity, read its sidecar `solutionTag` and reuse it.
7. Ask permission to test, then execute, poll, debug. Cap at 3 cycles.
8. Render a final report inline with a clickable canvas link.

If the user's request is purely about a **code node** (a reusable JS block, not a workflow), hand off to `/ai-builder:code-node-build` instead — it follows the same Plan/Develop/Test rhythm but scoped to a single code node. If the request is purely about a **Memory or Collection** (RAG ingestion, a knowledge base, a data table), hand off to `/ai-builder:data-build` instead. When a workflow needs a Memory or Collection that doesn't exist yet, run `/ai-builder:data-build` first to set up the data layer, then resume here.

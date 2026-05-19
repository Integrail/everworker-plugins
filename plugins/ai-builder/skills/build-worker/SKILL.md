---
description: Plan, develop, and test an Everworker Universal Worker (conversational reasoning agent) end-to-end from a natural-language request. Use this when the user wants a chat-style assistant, an interactive AI, a Slack-bot persona, or any open-ended agentic task that needs multi-step reasoning with a tool belt — not a deterministic pipeline.
---

The user wants to build an Everworker **Universal Worker** (reasoning agent). Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Scope this session to the playbook's **UNIVERSAL WORKERS** section.

Workers are built with **`worker_create` / `worker_update`** — structured-spec factory tools. You pass `name`, `instructions`, `providerId`, `model`, optional tool belt + skills + memories. The server assembles the canonical 2-node shape; you never type `methodId`, `nodeId`, or parameter names.

Run the **full Plan → Develop → Test cycle**:

1. **Decide it really is a Worker, not a Workflow.** Apply the "Universal Worker vs Workflow" decision rule. A Worker is for multi-step reasoning, interactive interfaces, or open-ended agentic tasks; a Workflow is a deterministic pipeline. If the requirement decomposes cleanly into a fixed graph, push back briefly and propose a Workflow instead via `/ai-builder:build`. Don't silently switch — confirm with the user.

2. **Plan like a solution architect.** Restate the business outcome in one sentence; map it to the smallest, most elegant combination of prompt + tools + skills. Don't enrich requirements. Reuse before building.
   - Discover what's already there: `mcp__ai_builder__workflow_search` (for `subWorkflowIds`), `mcp__ai_builder__providers_list` (for `providerId` and `apiProviderIds`), `mcp__ai_builder__memory_search` (for `vectorMemoryIds`), `mcp__ai_builder__worker_tools_list` (**always** — for `builtInTools` names).
   - If the user wants the worker to "know" or "remember" a body of content, hand off to `/ai-builder:data-build` first to create/populate the Memory, then come back and attach its `_id` to `vectorMemoryIds`.

3. **Present the plan inline** following the playbook's Design & Present structure adapted for workers:
   - **Problem** — one sentence.
   - **Approach** — the reasoning loop in plain English (what the worker does at each turn).
   - **Dependencies** — provider, sub-workflows, memories, MCP tools used.
   - **Tool belt** — bulleted list of every tool with a one-line when/when-not rule (this becomes the prompt's Tool usage policy section).
   - **Prompt outline** — section headers only (Role & purpose / Operating principles / Tool usage policy / Output style / Edge cases & refusals), with one-line summaries; the full text is rendered in the Develop step.
   - **Spec preview** — show the `worker_create` args block you intend to deploy (excluding the full `instructions` text, which you'll render in Develop). Model + provider + temperature + messageHistoryLimit live here.
   - **Possible follow-ups** — optional. Things you considered and chose not to include.
   - **Open questions** — only if blocking.
   - **Out of scope** — explicitly call out `slackConfig` if the user mentioned Slack: surface a note that Slack wiring lives in the form-based UI at the edit URL.

4. **Wait for explicit user approval.** A clarification answer is not approval.

5. **Develop** — workflow-as-code discipline applies, with a smaller surface:
   - Write the canonical spec JSON to `./everworker-workflows/<slug>.worker.json` (slug = kebab-case of the worker name). The file contains exactly the args you'll pass to `worker_create` — nothing more, nothing less. The hook compares byte-for-byte.
   - **Apply the solution tag (if any) to every taggable entity created or modified — see PLAYBOOK § SOLUTION TAGS.** Include it in the spec's `tags` array; if you reused an existing on-disk worker, read its sidecar `solutionTag` and propagate it. Sub-workflows and code nodes built or modified in the same task get the same tag.
   - Call `mcp__ai_builder__worker_create` with the spec.
   - Write the sidecar `./everworker-workflows/<slug>.worker.meta.json` with `{ workerId, kind: "worker", solutionTag?, lastDeployedAt, lastDeployedHash, everworkerUrl }`.
   - You do **not** assemble nodes, agentConfig, studioData, methodIds, or parameter wiring. The server handles all of that.

6. **Ask permission to test, then test.** Execute the worker with a representative `userMessage` via `mcp__ai_builder__worker_execute` (pass plain `userMessage: "..."` — the tool wraps it as `IChatMessage` server-side). Do **not** use `workflow_execute` for workers; it expects `userMessage` as an object and will produce `content: null` errors with a plain string. Poll with `workflow_execution_status`. Inspect:
   - `{{1.result.content}}` — does the reply match the prompt's stated style? Render as markdown in the test report.
   - `{{1.result.toolCalls}}` — did the worker call the right tools with sensible arguments? Skip a tool that shouldn't have been called? Use a tool that shouldn't have been there?
   - If something looks off, iterate: edit the local spec → `worker_update` with merged fields → re-test. Cap fix-and-retry at **3 cycles**, then surface the chat link and ask the user to verify interactively.

7. **Final report** — render a short markdown summary inline with both clickable links:
   - `[<Worker Name>](${user_config.everworker_url}/universal/edit/<workerId>)` — editor for fine-tuning (Slack, advanced settings).
   - `[Chat with <Worker Name>](${user_config.everworker_url}/universal/chat/<workerId>)` — chat tester.

If the user's request is actually a deterministic pipeline, hand off to `/ai-builder:build` instead. If it's a code node, hand off to `/ai-builder:code-node-build`. If it's a Memory or Collection only, hand off to `/ai-builder:data-build`.

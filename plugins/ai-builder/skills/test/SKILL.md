---
description: Test an existing Everworker AI Workflow. Executes it, polls for results, and reports per-node pass/fail. Use when the user wants to run a workflow.
---

The user wants to test a workflow. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Run **Test only**:

1. Use `mcp__ai_builder__workflow_search` (or `worker_search` for Universal Workers) to resolve the target if the user gave a name; otherwise use the provided ID.
2. `mcp__ai_builder__workflow_read` to confirm the structure and prepare `inputParams`.
3. Ask the user for permission to execute (one approval covers all retries within this task).
4. `mcp__ai_builder__workflow_execute` to start the run, then poll `mcp__ai_builder__workflow_execution_status` in a short loop. Echo the `executionId` to the user once before the first poll. Sleep **5 seconds** between polls using the `Bash` tool (`sleep 5`); the MCP tool itself returns immediately and *should* include `nextPollAfterMs: 5000` while running — treat it as a hint, not a contract, and fall back to 5s if it's missing, null, zero, or non-numeric. Stop at `completed` / `failed`. **Cap at 30 iterations (~2.5min).** On a transient poll error, retry the same call up to 3 consecutive times; on the 4th consecutive error, abort and tell the user the executionId so they can resume later.
5. On failure, drill into individual nodes via `nodeId`, debug, fix the **local file** first if a code change is needed, then `workflow_update`, then re-test.
6. Cap at 3 test → debug → fix cycles. After that, report current state and stop.
7. Render results inline as a status table with a clickable canvas link.

If the target is a **Universal Worker** (use `worker_read` instead of `workflow_read` to resolve), adapt the test flow:
- Execute via `mcp__ai_builder__worker_execute` (plain `userMessage: string` + optional `sessionId`, `messageHistoryLimit`) — **not** `workflow_execute`. Workers expect an `IChatMessage` shape on the input_node; `worker_execute` wraps the plain string server-side.
- A single execution is a single chat turn. Render `{{1.result.content}}` as markdown and summarise `{{1.result.toolCalls}}` (which tools fired, with what arguments).
- Don't try to test multi-turn conversation end-to-end — cap at 3 turns max, then surface `${user_config.everworker_url}/universal/chat/<workflowId>` and let the user verify by chatting with it.
- The final link is the editor URL: `${user_config.everworker_url}/universal/edit/<workflowId>` (not the canvas URL).

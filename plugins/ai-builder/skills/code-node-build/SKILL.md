---
description: Build, modify, or test an Everworker Code Node (a reusable JavaScript block usable inside workflows). Use when the user wants to create, edit, or debug a code node.
---

The user wants to work on an Everworker Code Node. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Scope this session to the playbook's **CODE NODES** section. Before drafting any code, call `mcp__ai_builder__custom_node_guidelines` once — it returns the canonical, server-maintained guide for VM context, allowed APIs, banned patterns, and timeout limits.

Run the focused **Plan → Develop → Test** loop for a single code node:

1. **Clarify** — what input shape, what output shape, what the code should do. If the user mentioned an existing code node by id or name, `mcp__ai_builder__custom_node_read` it first and render a short summary so you both agree on the starting point.
2. **Draft locally** — write `./everworker-workflows/<slug>.code.js` (the JS body) and `./everworker-workflows/<slug>.code.schema.json` (`{ name, description, inputSchema, outputSchema, tags?, timeoutMs? }`).
3. **Deploy** — `mcp__ai_builder__custom_node_create` for new nodes, `mcp__ai_builder__custom_node_update` for existing ones. **Apply the solution tag (if any) to every taggable entity created or modified — see PLAYBOOK § SOLUTION TAGS.** When opening an existing on-disk code node, read its sidecar `solutionTag` and reuse it; when adding a code node to an existing solution, find the slug from a sibling sidecar in the same directory. Write the `<slug>.code.meta.json` sidecar on success (`codeNodeId`, `kind: "code-node"`, `solutionTag?`, `createdInSession: true` for new, `false` for updates of remote-origin nodes, ISO timestamp, SHA-256 hash, `everworkerUrl`).
4. **Confirm before editing remote-origin nodes** — if the sidecar's `createdInSession` is `false` (or absent), STOP, render the proposed change as a markdown diff, and wait for the user's explicit "go" before deploying. Write `confirmedAt` into the sidecar after their confirmation.
5. **Test** — `mcp__ai_builder__custom_node_execute` with sample `inputData` matching `inputSchema`. Inspect `output` and `logs`. Cap fix-and-retry at **3 cycles**, then report and let the user steer.
6. **Final report** — render a short markdown summary inline: what changed, the on-disk files written, and a clickable link to the code node in the Everworker UI: `[<name>](${user_config.everworker_url}/specialized/code-node/<codeNodeId>)`.

If the user asks you to wire the code node into a workflow afterwards, hand off to `/ai-builder:develop` or `/ai-builder:build` — those flows know how to reference the code node via `operationReference: { methodId: "code_node", codeNodeId: "<id>" }` with parameters mapped from upstream nodes.

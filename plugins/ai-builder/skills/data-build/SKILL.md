---
description: Plan, build, populate, and test Everworker Memories (vector RAG stores) and Collections (typed data tables, optional vector RAG). Use when the user wants to set up the data layer that workflows will read from — RAG ingestion, knowledge bases, structured tables.
---

The user wants to set up a data store on Everworker — a Memory, a Collection, or both. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Scope this session to the playbook's **MEMORIES**, **COLLECTIONS**, **MEMORY vs COLLECTION**, and **DESTRUCTIVE-ACTION GUARDRAIL** sections.

Run a focused **Plan → Develop → Test** loop:

1. **Research** — list what already exists (`mcp__ai_builder__memory_search`, `mcp__ai_builder__collection_search`). Don't propose creating a duplicate. If the user mentioned a specific store by id or name, `_read` it first and surface a short summary.
2. **Pick the right primitive** — apply the Memory-vs-Collection decision rule. If the user asked for the wrong one (e.g. "a memory to store customer records with fields"), push back briefly with the rule and propose the alternative. Do not silently switch — confirm with the user.
3. **Plan inline** — render a short markdown plan: which primitive, name, embedder model + chunk size (Memory) or `jsonSchema` + `vectorFields` (Collection), where data comes from (text / urls / local files), and how a workflow will consume it (which node — `vector_search`, `find_in_collection`, `save_to_collection`). Wait for explicit user approval before creating anything. A clarification answer is not approval.
4. **Create** — `mcp__ai_builder__memory_create` or `mcp__ai_builder__collection_create`. Record the returned id.
5. **Ingest / populate** — for Memories: `mcp__ai_builder__memory_ingest` (one of `text`, `url`, `filePath`) per source, with a meaningful `title` and stable `docId`. For Collections: `mcp__ai_builder__collection_item_upsert` with rows that match the `jsonSchema`. For local files, only use absolute paths under the user's cwd.
6. **Verify retrieval** — `mcp__ai_builder__memory_item_search` (Memories) or `mcp__ai_builder__collection_item_search` / `mcp__ai_builder__collection_item_list` (Collections) with a representative query the user would actually run. Surface the top 1-3 results inline so the user can sanity-check relevance. Cap fix-and-retry at **3 cycles**, then report and let the user steer.
7. **Destructive ops** — before any `*_delete`, `clearAll`, or `*_update` that changes the embedder / chunkSize / vectorFields, follow the playbook's destructive-action guardrail: summarise the impact, wait for explicit `confirm`, then act.
8. **Final report** — render a short markdown summary inline: what was created / populated, sample retrieval output, and a clickable link to the resource in the Everworker UI:
   - Memory: `[<name>](${user_config.everworker_url}/memory-collection/<memoryId>)`
   - Collection: `[<shortName>](${user_config.everworker_url}/collections/<collectionId>)`

If the user asks to wire the data store into a workflow afterwards, hand off to `/ai-builder:develop` or `/ai-builder:build` — those flows know how to reference it via `vector_search`, `find_in_collection`, or `save_to_collection`.

Note: Memories and Collections are **server-side data**, not workflow source code — there is no on-disk sidecar discipline for items, and the PreToolUse hook does not gate `memory_*` / `collection_*` calls. Safety lives in the destructive-action guardrail above.

**Solution tags:** Memories and Collections **do not support server-side tags** — they have no `tags` field. When this data store is part of a multi-entity solution, record the `solutionTag` for cross-reference in any local notes / sidecars you keep, but skip it on the server. See PLAYBOOK § SOLUTION TAGS for the full rule.

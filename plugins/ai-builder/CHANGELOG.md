# Changelog

All notable changes to the `ai-builder` plugin (previously `everworker-workflows`) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Versioning convention.** The plugin version follows the MCP **contract version** advertised by the Everworker server at `/api/v1/agents/health` → `data.pluginContract`. The plugin's `plugin.json` declares `x-everworker.minServerContract` — the SessionStart hook warns if the server is older than that. When a breaking contract change ships, the previous-contract plugin is republished as a parallel channel (`ai-builder-v0.7@everworker`, etc.) so users on stale self-hosted servers can stay on a matching plugin.

## [0.10.0] — Unreleased

### Added — canvas-friendly node layout

- **PLAYBOOK.md § NODE LAYOUT** — new section. Every `workflow_create` /
  `workflow_update` now emits `studioData.nodes[].position` explicitly. The
  server's array-iteration-index fallback positioner is bypassed.
- **Layout algorithm.** Topological order from `{{nodeId.field}}` dependencies,
  single column (`x = 400`), `BASE_SPACING = 200`, extra `+80px` of gap before
  fan-in and after fan-out nodes, final `y` snapped to the canvas's 16-pixel
  grid. Tie-break by ascending `nodeId` for deterministic output.
- **Preservation rule.** On every update, positions already in the local
  `<slug>.json`'s `studioData.nodes[]` (sourced from the canvas via the drift
  flow) are carried through verbatim. The skill only computes positions for
  brand-new nodeIds. **Canvas-side drags are never overwritten.**
- **Drift handling carve-out.** The Update flow's drift check now silently
  resyncs the local file when the only remote difference is inside
  `studioData.nodes[].position` / `.measured`. Position-only drift is benign;
  any other body difference still stops and prompts.
- `build` and `develop` skills point at the new section.

### Why
- The server fallback laid nodes out by array order, not execution order, so
  workflows looked scrambled in the canvas. Users would drag every node into
  place — then the next CC update would re-scramble them because the skill
  didn't preserve positions.

### Non-breaking
- Server `generateStudioData` is unchanged; it still preserves whatever the
  caller passes (`helpers.ts:185`).
- No new MCP tool, no contract bump, no feature flag — the wire shape was
  always accepted; the playbook just teaches the skill to use it.

## [0.9.0] — Unreleased

### Added — Webhooks + Schedules

Two new first-class Everworker primitives are now plugin-addressable:

- **Webhooks** — inbound HTTP triggers that fan out to one or more Universal
  Workers. New tools:
  `webhook_search`, `webhook_read`, `webhook_create`, `webhook_update`,
  `webhook_delete`, `webhook_regenerate_secret`. Six auth methods supported
  (`secret_header`, `hmac_signature`, `bearer_token`, `api_key`,
  `custom_header`, `slack_auth`); two execution modes (`sync` / `async`).
- **Schedules** — recurring cron-driven executions of existing workers /
  workflows. New tools:
  `schedule_search`, `schedule_read`, `schedule_create`, `schedule_update`,
  `schedule_delete`, `schedule_toggle`, `schedule_run_now`. Standard 5-part
  cron + shorthand (`@daily`, `@hourly`, etc.); IANA timezone support;
  start/end window + `maxRuns` cap.
- **New slash commands**: `/ai-builder:webhook-build` and
  `/ai-builder:schedule-build`. Both follow the same shape as
  `/ai-builder:data-build` — research, plan, mutate with destructive-action
  guardrails. The schedule skill is **schedule-existing-only** — it never
  builds the target worker/workflow; it hands off to `/ai-builder:build` or
  `/ai-builder:build-worker` when the target is missing.
- **PLAYBOOK.md** gained **WEBHOOKS** and **SCHEDULES** sections covering
  when to reach for each, the tool flow, auth/cron rules, secret handling,
  and anti-patterns. **SOLUTION TAGS** table updated — webhooks are exempt
  (no `tags` field server-side); schedules support tags.
- **MCP contract bumped to `0.8.0`** with two additive feature flags:
  `webhook_crud`, `schedule_crud`. Plugin manifest's `minServerContract`
  bumped to `0.8.0`. Stale servers print a session-start warning and the new
  skills refuse cleanly; unrelated skills (build, data-build, build-worker)
  continue to work.
- Total exposed MCP tools: **55** (was 42).

### Why
- Webhooks and Schedules were the last two first-class Everworker primitives
  not addressable from the plugin. With them in, the AI Builder methodology
  covers the full lifecycle: trigger (webhook / schedule) → reason (worker)
  → integrate (workflow / code node) → store (memory / collection).

### Non-breaking
- Every new tool is additive. Existing skills, workflows, and sidecars
  continue to work unchanged.
- Webhooks and Schedules are **server-side data** (like Memories and
  Collections) — no workflow-as-code on disk, no PreToolUse hook gating.

## [0.8.0] — Unreleased

### Added — server-version handshake + multi-instance docs
- **Server** advertises `pluginContract` and `supportedFeatures` on
  `/api/v1/agents/health`. These are sourced from a new
  `imports/v25/tools/custom/workflowBuilder/pluginContract.ts` constants file
  so the workflow-builder MCP code owns its own version, independent of the
  container build version.
- **Plugin manifest** carries `x-everworker.minServerContract` and
  `x-everworker.requiredFeatures`. The SessionStart hook (`health-check.sh`)
  reads them, compares against the server response, and emits structured
  warnings to stderr when:
  - server contract < plugin minimum (deploys will likely fail),
  - required features are missing from the server's `supportedFeatures`,
  - server contract > plugin (informational — refresh suggested).
- **`PLAYBOOK.md` § VERSION COMPATIBILITY** — new section instructing the
  skill to treat session-start contract warnings as the real root cause when
  MCP errors land, rather than silently retrying.
- **README** gained a "Multiple Everworker instances" section documenting the
  project-scoped `userConfig` override pattern (drop a `.claude/settings.json`
  in each repo). No plugin code change — this works today via Claude Code's
  per-project config resolution.
- **Release tooling.** New top-level `scripts/release-plugin.sh` mirrors the
  plugin directory + `marketplace.json` from this repo into a local clone of
  the public marketplace repo. One-way sync. Does not push. Documented in
  `scripts/README.md`.

### Why
- A user on plugin `0.8.0` talking to a self-hosted server pinned at `0.6.x`
  would previously hit opaque MCP errors or silent field drops. The handshake
  makes the gap visible at session start.
- Multiple-instance use ("I work on customer A in this repo, customer B in
  that one") needed no plugin change — just documentation of the override
  pattern Claude Code already supports.
- The public marketplace repo cannot run CI, so the release path is an
  explicit, reviewable local step rather than an automated workflow.

### Non-breaking
- `pluginContract` and `supportedFeatures` are additive on the health
  response. Older plugins ignore them.
- Older servers (pre-0.7.0 contract) omit the fields entirely; the new hook
  prints a single info-level warning and continues.

## [0.7.0] — Unreleased

### Added — solution-tag pattern
- **`worker_create` / `worker_update`** now accept a `tags: string[]` field on the
  spec. The tag list is persisted on the underlying `IIAFAgent` document and
  surfaces in `worker_read` / `worker_search`.
- **`workflow_create` / `workflow_update`** now accept `workflowJson.tags`
  (always existed at the schema level, now documented + always passed through).
  `workflow_search` returns `tags` alongside the other summary fields.
- **`worker_search` and `workflow_search`** accept an optional `tags: string[]`
  filter — when set, only entities that carry ALL of the listed tags are
  returned. Use with a `solution:<slug>` tag to enumerate every workflow /
  worker in a solution.
- **`PLAYBOOK.md` § SOLUTION TAGS** — new section, mandates a single
  `solution:<slug>` tag on every taggable entity in a multi-entity solution.
  Memories and Collections (no `tags` field server-side) are exempt; their
  link to the solution lives in the on-disk sidecar's `solutionTag` instead.
- Plan / Develop / Build / Build-Worker / Code-Node-Build skills cross-reference
  the new section and require the tag to be applied at deploy time.
- Sidecar `meta.json` files gain an optional `solutionTag` field.

### Why
- A solution is rarely one entity. Without a marker, the workspace turns into
  an alphabetical soup. One shared tag means a single search filter returns
  the entire solution.

### Non-breaking
- All new tag-related parameters are optional. Single-entity tasks skip the
  tag entirely. Pre-tag entities are not retroactively tagged — when working
  on one that lacks a `solution:` tag, the skill asks before adding one.

## [0.6.0] — Unreleased

### Added — factory-pattern Worker CRUD (breaking)
- **`worker_create`** — Universal Worker factory. Takes **structured fields**
  (`name`, `instructions`, `providerId`, `model`, `builtInTools` by name,
  `subWorkflowIds`, `apiProviderIds`, `mcpTools`, `vectorMemoryIds`,
  `temperature`, `messageHistoryLimit`, `workersMemory`). Server assembles the
  canonical 2-node shape, enforces `methodId: "generic_llm"`, mirrors
  `instructions` into `agentConfig[1].promptTemplate.unifiedInstructions`,
  expands `builtInTools` names into full `IToolFunction` objects from
  `StandardSupportedTools` (rejects unknown names), and applies defaults for
  `advancedSettings`. **The LLM never types the node graph.**
- **`worker_update`** — partial update by `workerId`. Merges the supplied fields
  with the current spec (reconstructed from the persisted doc) and re-assembles.
- **`worker_read`** — returns the structured spec (the args shape) for editing
  or round-tripping to disk. No raw IIAFAgent shuffling.
- **`worker_search`** — name/description search restricted to `isUniversal: true`.
- **`worker_execute`** — single chat turn against a Universal Worker. Takes a
  plain `userMessage: string` and wraps it as an `IChatMessage`
  (`{role:'user', content:'...'}`) before handing to the orchestrator. Use this
  to test workers — `workflow_execute` expects an `IChatMessage` object and
  passing a plain string yields `content: null` errors at the LLM API.
- **`worker_delete`** — soft-delete.
- Total exposed tools: **42**.

### Changed (breaking)
- **`workflow_create` no longer accepts `isUniversal`.** Pass it `workflowJson`
  with `isUniversal: true` and it returns an error pointing at `worker_create`.
- **`workflow_update` rejects targets where `isUniversal === true`.** Use
  `worker_update` instead.
- **`workflow_search` excludes Universal Workers.** Use `worker_search`.
- On-disk worker convention is now the **spec args** (the structured fields
  passed to `worker_create`), not the full IIAFAgent JSON. Sidecar key is
  `workerId` (legacy `workflowId` still accepted for compatibility with
  pre-existing sidecars).
- **Playbook UNIVERSAL WORKERS section is dramatically shorter** — the
  canonical-shape, hard-rules, parameter-name, and JSON-assembly sections are
  gone because none of those concerns exist for the LLM anymore. Replaced with
  a single spec table.
- `build-worker` skill rewritten around `worker_create` instead of
  `workflow_create({ isUniversal: true })`.
- `PreToolUse` hook gates `worker_create` / `worker_update` with byte-for-byte
  spec comparison against `<slug>.worker.json`.

### Why
- Universal Workers have **one possible shape** (always 2 nodes, always
  the same `methodId` and parameter names). Exposing the raw JSON to the LLM
  was an invitation for typos like `generic_llm_universal` (a different node —
  stateless workflow LLM, expects a `messages` array) which produced runtime
  errors like `"messages is not iterable"`. The factory pattern makes that
  entire class of bug structurally impossible.
- This brings workers in line with Memory / Collection / Code Node creation,
  all of which already use the structured-factory pattern. The pattern was
  inconsistent and is now uniform.

## [0.5.0] — Unreleased

### Added
- **Universal Worker** support — `/ai-builder:build-worker` runs a full
  Plan → Develop → Test cycle for a conversational reasoning agent (LLM brain +
  tool belt). Same DB entity as a Workflow (`isUniversal: true`), but distinct
  concept: separate slash command, separate planning, separate prompt-engineering
  + tool-selection guidance, separate on-disk filename (`<slug>.worker.json`).
- New **UNIVERSAL WORKERS** section in `PLAYBOOK.md` covering:
  the "Universal Worker vs Workflow" decision rule (workers are for multi-step
  reasoning, interactive interfaces, and open-ended agentic tasks — don't reach
  for a worker just because LLMs are involved); canonical 2-node shape
  (`input_node` at `nodeId: 0`, `generic_llm` at `nodeId: 1`); prompt-engineering
  structure and quality bar; tool-selection rules; skills (`workers`, `providers`,
  `mcpTools`, `vectorMemories`); local file convention; test flow; final-report
  URLs (`/universal/edit/<id>` + `/universal/chat/<id>`).
- New **MCP tool** `worker_tools_list` — returns the live `StandardSupportedTools`
  catalogue (canvas-only tools excluded) so the playbook never drifts from the
  actual server-side built-in tool surface. Total exposed tools: **36**.
- Cross-references in `plan`, `develop`, and `test` skills that point chat-style
  / agentic intents at `/ai-builder:build-worker`, and adapt the test report for
  workers (chat-turn rendering, `toolCalls` summary, editor URL).

### Changed
- `scripts/check-local-copy.sh` now discriminates on `workflowJson.isUniversal`:
  Universal Workers deploy from `<slug>.worker.json` + `<slug>.worker.meta.json`;
  Workflows continue to deploy from `<slug>.json` + `<slug>.meta.json`.

### Out of scope
- `slackConfig` (turning a worker into a Slack bot) — surface a note pointing
  to the form-based UI at `/universal/edit/<id>`.

## [0.4.0] — Unreleased

### Changed
- **Renamed plugin** from `everworker-workflows` to `ai-builder` to match the
  in-product AI Builder feature. New slash commands: `/ai-builder:build`,
  `/ai-builder:plan`, `/ai-builder:develop`, `/ai-builder:test`,
  `/ai-builder:code-node-build`, `/ai-builder:data-build`.
- **Renamed MCP server alias** `mcp__everworker__*` → `mcp__ai_builder__*`.
- **Plugin directory** moved from `plugins/everworker-workflows/` to
  `plugins/ai-builder/`.
- **Marketplace name unchanged** (`everworker`). Re-install via
  `/plugin uninstall everworker-workflows` then
  `/plugin install ai-builder@everworker`.

### Compatibility
- On-disk workflow folder (`./everworker-workflows/` in user repos) is
  **unchanged** to preserve compatibility with already-committed workflow JSONs
  and code-node sidecars.
- Server endpoint (`/mcp/workflow-builder`) and server-side identifiers are
  unchanged.

## [0.3.0] — Unreleased

### Changed
- **Planning is now solution-architect-shaped.** The Plan phase starts by
  restating the business outcome in one sentence, maps it to the smallest
  combination of platform features, and justifies every node in one sentence.
  No requirement enrichment, no bonus features — tempting additions go in a
  *Possible follow-ups* section, not in the plan.
- **Workflow shape is rendered as a one-line text diagram with `→` arrows**
  instead of a mermaid block. Branches use `┬` / `└─`; parallel uses `‖`.
  Mermaid is removed from the playbook and skill instructions.

### Added
- Full **Memory** CRUD via MCP: `memory_search`, `memory_read`, `memory_create`,
  `memory_update`, `memory_delete`, `memory_item_search`, `memory_item_list`,
  `memory_ingest`, `memory_item_delete` (9 tools).
- Full **Collection** CRUD via MCP: `collection_search`, `collection_read`,
  `collection_create`, `collection_update`, `collection_delete`,
  `collection_item_search`, `collection_item_list`, `collection_item_get`,
  `collection_item_upsert`, `collection_item_delete` (10 tools). Total exposed
  tools: **35**.
- **RAG ingestion** through Claude Code via `memory_ingest`: pass `text`, `url`,
  or `filePath` (absolute, ≤ 50 MB, allowed extensions: .md .txt .pdf .html
  .csv .xlsx .json). The skill uploads + chunks + embeds server-side.
- New `/ai-builder:data-build` slash command — focused
  Plan / Develop / Test loop for one Memory or Collection (or both).
- New **MEMORIES**, **COLLECTIONS**, and **MEMORY vs COLLECTION** sections in
  `PLAYBOOK.md`, plus a **DESTRUCTIVE-ACTION GUARDRAIL** section requiring
  in-band `confirm` before any `*_delete`, `clearAll`, or embedder / chunkSize /
  vectorFields change.
- One-line handoff hooks in `develop`, `build`, and `plan` skills: when a
  workflow needs a Memory or Collection that doesn't exist yet, the skill now
  hands off to `/ai-builder:data-build` first.

## [0.2.0] — Unreleased

### Added
- Full **Code Node** CRUD via MCP: `custom_node_create`, `custom_node_update`,
  `custom_node_execute`, `custom_node_guidelines` are now exposed alongside the
  existing `custom_node_search` and `custom_node_read` (16 tools total).
- New `/ai-builder:code-node-build` slash command — focused
  Plan/Develop/Test loop for a single code node.
- New **Code Nodes** section in `PLAYBOOK.md` covering the VM context, banned
  patterns, schemas, workflow-wiring (`operationReference: { methodId: "code_node",
  codeNodeId }`), and the iteration loop.
- Workflow-as-code discipline extended to code nodes: each node lives on disk as
  `<slug>.code.js` + `<slug>.code.schema.json` + `<slug>.code.meta.json`. The
  `PreToolUse` hook blocks `custom_node_create` / `custom_node_update` calls
  that don't match the on-disk pair byte-for-byte.
- **"Ask before editing"** guardrail: when the local sidecar's
  `createdInSession` is not `true`, `custom_node_update` is blocked until the
  skill renders the proposed change as a markdown diff, the user confirms, and
  the skill writes a fresh `confirmedAt` timestamp into the sidecar.

## [0.1.0] — Unreleased

Initial release.

### Added
- Shared `PLAYBOOK.md` methodology that plans, develops, and tests Everworker
  AI Workflows. Each skill loads the playbook and runs it inline in the
  current session (no sub-agent delegation, so MCP access is preserved).
- Slash commands: `/ai-builder:plan`, `/ai-builder:develop`,
  `/ai-builder:test`, `/ai-builder:build`.
- HTTP MCP client wired to Everworker's `/mcp` endpoint, JWT-authenticated.
- `SessionStart` health check against `/api/v1/agents/health`.
- `PreToolUse` guard that requires a local copy of every workflow JSON before
  it is created or updated remotely.
- `userConfig` for `everworker_url` (settings.json) and `everworker_jwt`
  (OS keychain).

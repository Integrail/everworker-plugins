# Changelog

All notable changes to the `ai-builder` plugin (previously `everworker-workflows`) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Versioning convention.** The plugin version follows the MCP **contract version** advertised by the Everworker server at `/api/v1/agents/health` → `data.pluginContract`. The plugin's `plugin.json` declares `x-everworker.minServerContract` — the SessionStart hook warns if the server is older than that. When a breaking contract change ships, the previous-contract plugin is republished as a parallel channel (`ai-builder-v0.7@everworker`, etc.) so users on stale self-hosted servers can stay on a matching plugin.

## [0.15.0] — Unreleased

### Added — Google web search hint

Surfaced the `rapidapi.websearch` provider in both the `providers_list` tool description and the PLAYBOOK's Integration section. The plugin will now tell the LLM, the moment it inspects available providers, that this is the provider to reach for whenever a workflow needs Google-style search results (or current/news content past the LLM's cutoff). Includes the `standard_api_call` parameters (url + path + GET + URL-encoded `q`) and notes that Universal Workers should prefer the built-in `web_search` tool, which wraps the same provider.

## [0.14.0] — Unreleased

### Fixed — `workflow_execution_status` no longer sleeps server-side

Removed the `delaySeconds` parameter from `workflow_execution_status`. The tool now returns immediately. When the workflow is still running, the response includes `nextPollAfterMs: 5000` as a hint — the LLM polls in a client-side loop (`Bash sleep 5`) instead of holding the MCP connection open. This eliminates the hang the planner used to hit when picking a long delay (60–90s) that exceeded the MCP tool-call timeout. The PLAYBOOK and the `test` / `build-worker` skills now spell out the loop pattern with a 30-iteration cap, 3-strikes transient-error retry, and a defensive fall back to a fixed 5s wait if `nextPollAfterMs` is absent / null / non-numeric.

## [0.13.0] — Unreleased

### Fixed — webhook targets are Workflows, not Universal Workers

The webhook tool descriptions and the `webhook-build` skill incorrectly said webhooks fan out to Universal Workers. They actually target **Workflows** — Universal Workers expect a chat-style userMessage/session and are not valid webhook targets. The underlying field is legacy-named `workerIds`, but every ID it holds must reference a Workflow. The plugin doc, the PLAYBOOK's WEBHOOKS section, and the `webhook-build` skill now state this correctly so the LLM stops looking for the wrong entity (and stops telling users to wrap workflows in workers).

### Added — plugin/MCP permissions aligned with Everworker web interface

Plugin/MCP scope only — engine code untouched.

- **`current_user_get_capabilities` (new MCP tool)** — returns the operator's role and a capability matrix (`createWorkflows`, `createWorkers`, `createSchedules`, `createCustomNodes`, `manageWebhooks`, `executeWorkflows`, `readCatalogues`). Called first in the Plan phase so the planner can warn the user about role-limited steps before designing, instead of failing mid-execution.
- **Role-aware tool gates** — every workflow-builder write tool now mirrors the Everworker web interface's `allowedRoles` route guard:
  - Webhooks (search, read, create, update, delete, regenerate secret) → **Admin**.
  - Workflows, Universal Workers, Schedules, Custom Nodes (search / read / create / update / delete / execute / toggle / run_now) → **Builder**.
  - Read-only catalogue tools (`schema_get_*`, `providers_list`, `worker_tools_list`) and `workflow_execute` / `workflow_execution_status` are unchanged — they match the web interface's any-authenticated-user surfaces.
- **PLAYBOOK Permissions section** — documents the new rule and the capability cheat sheet.
- **Connect Claude Code modal** — shows the operator's current role and a role-aware caveat under the security notice, so the user knows what their token can and can't do before pasting it into Claude Code.

### Why

Without this, an `mcp:workflow-builder` JWT scope let a User-role token call tools that mutate resources the same user could never reach in the web interface (e.g. webhook creation, which the interface gates to Admin). The plugin now refuses those calls server-side and the planner stops drafting them in the first place.

## [0.11.0] — Unreleased

### Added — feedback-driven guideline & MCP polish

Round of fixes from a long real-world build. Plugin / MCP scope only — engine
code (validator, VM sandbox, template resolver, providers store) untouched.

- **Custom-node guidelines rewritten**:
  - Validator caveats section documents the regex false positives so the LLM
    avoids names like `obj.path`, `osVersion`, `process_data`. Errors are
    non-fatal — iterate by reading `validationErrors`.
  - Explicit **NOT available** section lists `URL`, `URLSearchParams`,
    `fs`/`path`/`os`/`child_process`, `require`/`import`, `process`/`global`,
    `eval`/`Function`, timers, web crypto, WebSocket — so the LLM doesn't
    emit code that won't compile.
  - **Building URLs without `URL()`** snippet — manual querystring assembly
    with `encodeURIComponent`.
  - Auth section reworded so `getToken` is the right answer for non-Bearer
    APIs (X-API-Key, X-KEY, apikey, query-string keys), not a footnote.
  - **`.result` wrapping** documented — `output = { companies: [...] }` is
    referenced as `{{N.result.companies}}` from a workflow.
  - **Strict template resolution** documented — missing keys throw, always
    emit documented keys (use `null` in error paths).
- **Secret-leak parity** — `custom_node_execute` and `workflow_execute` now
  share a token-shape detector (`findTokenShapedValue` in `toolHelpers.ts`)
  that scans inputs for OpenAI `sk-`, Slack `xox?-`, GitHub `gh?_`, AWS
  `AKIA`, Google `ya29.`, JWTs, and `Bearer …` patterns. Both tools refuse
  with a clear message pointing the LLM at provider configuration instead.
- **`providers_list.isConnected` now meaningful for service-auth providers**
  — previously only OAuth providers could report `true`. The flag is now
  derived per auth mode: OAuth uses the existing user-token check; app-token
  / service-auth checks the named token secret (with fallback to "any
  non-empty secret"); hybrid is true if either channel is configured. The
  tool description spells out the semantics.
- **PLAYBOOK § Parameter Templating** — adds a Custom Nodes bullet for
  `.result` wrapping and a "Strict template resolution" subsection.
- **workflow_create / workflow_update descriptions** — call out the strict
  template eval caveat so the LLM only references keys that are guaranteed
  to be present.

### Why
- Real-world build session surfaced multiple papercuts: validator false
  positives on `obj.path.x`, undocumented `.result` wrapping that broke a
  first workflow run, `URL` not in the sandbox, `isConnected: false` for
  API-key connectors that worked fine, and asymmetric secret-leak
  protection between the two `_execute` tools.

## [0.10.4] — Unreleased

### Fixed — runtime URL now injected directly into LLM context

- 0.10.1 wrote runtime values to `${CLAUDE_PLUGIN_ROOT}/runtime/runtime.json`
  and told the LLM to `Read` that file. But `${CLAUDE_PLUGIN_ROOT}` is NOT
  substituted in skill markdown either (same gotcha as `${user_config.X}`),
  so the LLM had to hunt for the file across plausible install paths —
  fragile and slow.
- **SessionStart hook now emits the runtime values as `additionalContext`**
  via the SessionStart hook JSON output protocol. Claude Code injects that
  text directly into the LLM's system context for the whole session.
  The LLM sees an `[ai-builder runtime]` block listing `everworker_url`,
  server contract, plugin version, and supported features — no file
  lookup needed.
- `runtime.json` is still written under the plugin root as a defensive
  fallback (gitignored), but the primary delivery channel is the injected
  context.
- **PLAYBOOK § RUNTIME INFO** rewritten — points at the injected context
  block instead of the file.

### Why
- A CC session reported having to grep for the runtime file across
  multiple plausible paths before finding it under the dev checkout. The
  hook-output channel makes the URL available structurally with no path
  guessing.

### Non-breaking
- The fallback file is still written, so older skill instructions that read
  it still work.

## [0.10.3] — Unreleased

### Fixed — workflow_create / workflow_update silently dropped studioData

- The `workflowJson` parameter schemas for both tools declared
  `{ name, description, tags, nodes, agentConfig }` but **not `studioData`**.
  The MCP framework's input validator strips fields not in the schema, so
  even when the LLM passed positions per § NODE LAYOUT, they never reached
  `execute()`. The server's `generateStudioData` fell back to the
  array-index column placement every time.
- Added a full `studioData` subschema to both tools — array of
  `{ id, type?, position: {x,y}, measured? }`. The LLM's positions now
  survive validation and are preserved verbatim by the server's existing
  preservation path in `helpers.ts:185-192`.

### Why
- Direct DB inspection of workflows created via the plugin showed
  y = -96, 54, 204 (server fallback, 150px spacing) even when the tool call
  payload visibly contained y = -96, 104, 304 (200px from the layout
  algorithm). Schema-level field stripping was the silent culprit.

### Non-breaking
- `studioData` was already optional in the TypeScript types and the
  preservation logic — only the JSON Schema was lying. Workflows that never
  passed studioData continue to work via the server fallback unchanged.

## [0.10.2] — Unreleased

### Fixed — node layout was being skipped by fresh sessions

- 0.10.0 added a § NODE LAYOUT section to the playbook, but the visible
  Create / Update flow steps still said only "draft the workflowJson" — so
  the LLM drafted the JSON without `studioData`, the server's fallback
  positioner kicked in (array-index column, 150px spacing), and workflows
  landed on the canvas in arbitrary order regardless.
- **PreToolUse hook** (`check-local-copy.sh`) now structurally enforces the
  rule: `workflow_create` and `workflow_update` are **blocked** when
  `workflowJson.studioData.nodes[]` doesn't carry a `{x,y}` position for
  every nodeId in `workflowJson.nodes[]`. Same shape as the existing local-
  copy + drift checks — the LLM gets an immediate block reason pointing at
  § NODE LAYOUT.
- **PLAYBOOK § Create flow / Update flow** rewritten to put studioData
  front-and-centre on step 1 / step 4 respectively, with an explicit
  "existing positions are sacred" rule on update.

### Why
- A fresh session created a workflow that landed in the DB with the server-
  fallback positions (y = -96, 54, 204; 150px gap) — exact evidence the LLM
  was ignoring the new layout rules. Burying enforcement in a section the
  LLM may not re-read in every session isn't reliable; the hook makes the
  rule structural.

### Non-breaking
- Workflows that already pass studioData are unaffected.
- Existing local files without studioData will now fail their next deploy
  attempt with a clear, actionable block reason — same pattern as the
  byte-equivalence and drift checks.

## [0.10.1] — Unreleased

### Fixed — URL hallucination in sidecars and final-report links

- **`${user_config.X}` is not substituted inside skill / playbook markdown.**
  Only `plugin.json` template substitution is supported by Claude Code. The
  LLM was reading the literal token `${user_config.everworker_url}` and
  fabricating a plausible value (typically `https://app.everworker.ai`),
  poisoning every `.meta.json` sidecar and every canvas link in final
  reports.
- **SessionStart hook now writes `${CLAUDE_PLUGIN_ROOT}/runtime/runtime.json`**
  containing the configured `everworkerUrl`, plus the server's reported
  contract / supported features / plugin version. No JWT (no secrets land in
  a file the LLM reads).
- **PLAYBOOK.md gained a § RUNTIME INFO** section instructing the skill to
  read `runtime/runtime.json` at session start and use its `everworkerUrl`
  verbatim wherever the playbook or any skill shows the
  `${user_config.everworker_url}` placeholder. Explicit "never hallucinate a
  URL" rule.

### Why
- A user pointed at a non-default Everworker URL noticed `everworkerUrl` in a
  fresh sidecar was wrong. Root cause: skill markdown templates aren't
  evaluated; the LLM had no actual access path to the configured URL.

### Non-breaking
- Existing skills keep using the `${user_config.everworker_url}` placeholder
  syntax in their final-report instructions — the playbook now teaches the
  LLM to substitute it from `runtime.json`. No skill rewrites needed.

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

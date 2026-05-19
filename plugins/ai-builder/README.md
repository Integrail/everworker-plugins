# ai-builder — Claude Code plugin

Plan, develop, and test [Everworker](https://everworker.ai) AI Workflows, Universal Workers (conversational reasoning agents), Code Nodes, Memories (vector RAG stores), and Collections (typed data tables) from inside Claude Code.

This plugin re-skins Everworker's in-product **AI Builder** as a Claude Code skill. The methodology is the same — Plan → Develop → Test, with a strict workflow-as-code discipline so every workflow JSON and every code node (its JS body + JSON schema) lives on disk before it ships to the server. Memories and Collections are server-side data — not stored on disk — so the discipline there is a destructive-action guardrail instead: the skill summarises and confirms before any deletion or embedder change. When editing a code node that wasn't created in the current session, the skill always pauses to confirm with you before deploying.

## Prerequisites

- A running Everworker instance you can reach over HTTP (local or remote).
- A JWT issued for your user with the workflow-builder MCP scope. Ask an admin if you don't have one. The JWT is stored in your OS keychain after install.
- `jq` available on `PATH` (used by the local-copy guard hook). On macOS: `brew install jq`.

## Install

The Everworker repo ships its own local marketplace at `.claude-plugin/marketplace.json`. One-time setup, from any directory:

```text
/plugin marketplace add /path/to/everworker
/plugin install ai-builder@everworker
```

After install, plain `claude` loads the plugin in any directory — no `--plugin-dir` flag. Claude Code prompts for `everworker_url` and `everworker_jwt` on first load.

If you pull plugin changes from the repo, run `/plugin marketplace update everworker` to re-sync.

### Upgrading from `everworker-workflows`

If you previously installed `everworker-workflows@everworker`, uninstall it and re-install under the new name:

```text
/plugin uninstall everworker-workflows
/plugin marketplace update everworker
/plugin install ai-builder@everworker
```

Existing on-disk workflows under `./everworker-workflows/` keep working — the folder name is intentionally unchanged. Anything in your saved memory / agent prompts referencing `mcp__everworker__*` tool names should be updated to `mcp__ai_builder__*`.

## What you get

| Slash command                       | What it does                                                                                                                                 |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `/ai-builder:build <req>`             | Full Plan → Develop → Test cycle for an AI Workflow. The default end-to-end flow.                                                                  |
| `/ai-builder:plan <req>`              | Research and present a plan only — no deploy. Use to scope before committing.                                                                      |
| `/ai-builder:develop`                 | Create a new workflow or modify an existing one. Skips planning and skips testing.                                                                 |
| `/ai-builder:test <id>`               | Execute a workflow, poll for results, debug failures node-by-node. Capped at 3 fix-and-retry cycles.                                               |
| `/ai-builder:code-node-build <req>`   | Build, modify, or test a Code Node (a reusable JS block usable inside workflows). Asks before editing any node not created in the current session. |
| `/ai-builder:data-build <req>`        | Plan, create, populate, and test a Memory (vector RAG store) or Collection (typed data table). Performs RAG ingestion from text, URLs, or local files. Confirms before any destructive op. |
| `/ai-builder:build-worker <req>`      | Plan, develop, and test a Universal Worker — a conversational reasoning agent with a curated tool belt. Use for chat assistants, Slack bots, and open-ended agentic tasks (not deterministic pipelines). |
| `/ai-builder:webhook-build <req>`     | Plan, create, edit, and delete a Webhook — an inbound HTTP trigger that fan-outs to one or more Universal Workers. Confirms before delete or secret rotation. |
| `/ai-builder:schedule-build <req>`    | Plan, create, edit, and delete a Schedule — a recurring cron-driven execution of an existing Universal Worker / Workflow. Schedule-existing-only; never builds the target. |

Each skill loads the shared playbook in `PLAYBOOK.md` and runs it in the current session, where the 55 MCP tools and Claude Code's local-file tools are available.

Memories, Collections, Webhooks, and Schedules are **server-side data** — they do not land on disk. The workflow-as-code rules below apply only to workflow JSON and code-node source.

## Workflow-as-code

Every workflow, Universal Worker, and code node you build lands on disk in `./everworker-workflows/` in your current working directory:

```
everworker-workflows/
├── summarise-error-logs.json            full workflowJson — the source of truth
├── summarise-error-logs.meta.json       { workflowId, kind: "workflow", lastDeployedAt, lastDeployedHash, everworkerUrl }
├── invoice-helper.worker.json           Universal Worker JSON (isUniversal: true)
├── invoice-helper.worker.meta.json      { workflowId, kind: "worker", lastDeployedAt, lastDeployedHash, everworkerUrl }
├── extract-emails.code.js               raw JS body of a code node
├── extract-emails.code.schema.json      { name, description, inputSchema, outputSchema, tags?, timeoutMs? }
└── extract-emails.code.meta.json        { codeNodeId, kind: "code-node", createdInSession,
                                            confirmedAt?, lastDeployedAt, lastDeployedHash, everworkerUrl }
```

- Commit the directory to your repo to get version control over your workflows and code nodes.
- The `PreToolUse` hook **blocks** any `workflow_create` / `workflow_update` / `custom_node_create` / `custom_node_update` deploy that doesn't have matching local files with byte-equivalent contents. This is intentional — it's the guarantee that nothing ships without an on-disk record.

**Solution tags.** When a single request produces more than one taggable entity (workflow + worker + code node), the playbook coins a `solution:<slug>` tag and applies it to every taggable entity in the set. Searching by that tag — via `workflow_search`, `worker_search`, or `custom_node_search` with `tags: ["solution:<slug>"]` — returns the whole solution as one bundle. Memories and Collections have no server-side `tags` field and are exempt; the link to them lives in their on-disk sidecar's `solutionTag` instead. See `PLAYBOOK.md` § SOLUTION TAGS for the full rule.
- For code nodes the hook adds one more guardrail: an update against a node that was *not* created in the current session is blocked until the skill renders the change as a markdown diff, the user confirms, and the skill writes a `confirmedAt` timestamp into the code-node sidecar.
- Drift handling: when updating, the skill reads the remote, hashes it, and compares against the sidecar. If the remote was edited out-of-band (e.g. via the Everworker canvas or the in-product code node editor), the skill stops and asks which side wins before doing anything destructive.

## Configuration

The plugin reads two `userConfig` values:

| Key              | Where it's stored      | Notes                                                                                          |
| ---------------- | ---------------------- | ---------------------------------------------------------------------------------------------- |
| `everworker_url` | `~/.claude/settings.json` | Base URL of your Everworker instance, no trailing slash. Default: `http://localhost:3000`.  |
| `everworker_jwt` | OS keychain               | JWT with the workflow-builder MCP scope. Update via `/plugin` if it expires.                |

To update either value: `/plugin` → select `ai-builder` → reconfigure.

### Multiple Everworker instances

The plugin is single-tenant per Claude Code session, but `userConfig` values can be overridden per project. To point different repos at different Everworker instances:

1. In each project repo, create `.claude/settings.json` with the project-local values:

   ```json
   {
       "pluginConfigs": {
           "ai-builder@everworker": {
               "options": {
                   "everworker_url": "https://customer-a.everworker.ai",
                   "everworker_jwt": "eyJ..."
               }
           }
       }
   }
   ```

   The key is `<plugin-name>@<marketplace-name>` — adjust the marketplace name if you installed the plugin from a marketplace other than `everworker`.

2. `cd` into a repo and start Claude Code — the plugin uses that repo's values.
3. To switch instances, `cd` to a different repo. Within a single CC session you cannot swap; restart in the new directory.

The default values (from `/plugin`) are used in any directory that doesn't override them.

### Server compatibility

The plugin and the Everworker server share an MCP contract version. On every session start the plugin reads `/api/v1/agents/health`, compares the server's `pluginContract` against `x-everworker.minServerContract` in `plugin.json`, and prints a warning to stderr if they don't match. The plugin always loads — the warning just tells you whether the two sides agree on the tool surface.

If your self-hosted Everworker lags behind the latest plugin version, either upgrade the server or install a plugin channel pinned to the previous contract (when a parallel channel is published; see `CHANGELOG.md` for the matching version).

## Troubleshooting

**"WARN: cannot reach $URL/api/v1/agents/health" at session start**
The plugin can't talk to your Everworker. Common causes: Everworker isn't running, the URL is wrong, or the JWT is invalid/expired. The plugin still loads — the next tool call will surface the underlying error.

**"PreToolUse hook blocked the deploy"**
The local workflow file is missing or its contents don't match the JSON the skill tried to deploy. Look at the hook's reason text — it tells you exactly which file to write or fix. This is a feature; don't try to bypass it.

**"Drift detected — remote was edited out of band"**
Someone (or you, via the canvas) changed the workflow on the server since the last deploy from this directory. Decide which side wins and tell the skill — it won't do anything destructive until you do.

**`mcp__ai_builder__*` tools don't appear in `/mcp`**
Check that the Everworker server has the workflow-builder MCP adapter enabled (server-side feature), and that your JWT has the workflow-builder scope.

## Repository layout

```
ai-builder/
├── .claude-plugin/
│   └── plugin.json                  manifest, mcpServers, userConfig
├── PLAYBOOK.md                       shared methodology — full Plan/Develop/Test playbook
├── skills/
│   ├── plan/SKILL.md
│   ├── develop/SKILL.md
│   ├── test/SKILL.md
│   ├── build/SKILL.md
│   ├── build-worker/SKILL.md
│   ├── code-node-build/SKILL.md
│   └── data-build/SKILL.md
├── hooks/
│   └── hooks.json                   SessionStart health check + PreToolUse local-copy guard
├── scripts/
│   ├── health-check.sh
│   └── check-local-copy.sh
├── CHANGELOG.md
└── README.md
```

## Reference

- In-product AI Builder docs: `docs/AI-Builder-Agent.md` in the Everworker repo.
- Claude Code plugin authoring: `docs/Claude-Code-Plugin-Development.md` in the Everworker repo.

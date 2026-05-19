---
description: Plan, create, modify, and delete Everworker Schedules — recurring cron-driven executions of existing Universal Workers / Workflows. Use when the user wants something to run on a timetable.
---

The user wants to work with an Everworker Schedule. Their request:

> $ARGUMENTS

**Read `${CLAUDE_PLUGIN_ROOT}/PLAYBOOK.md` and follow it now, in this session — do NOT delegate to a sub-agent.** The current session has the `mcp__ai_builder__*` tools available; sub-agents will not.

Scope this session to the playbook's **SCHEDULES** and **DESTRUCTIVE-ACTION GUARDRAIL** sections.

**This skill is schedule-existing-only.** It never creates the worker or workflow it schedules. If the target doesn't exist yet, stop and hand off to `/ai-builder:build` (for a workflow) or `/ai-builder:build-worker` (for a Universal Worker), then come back.

Run a focused **Plan → Develop → Test** loop:

1. **Research** — list what already exists (`mcp__ai_builder__schedule_search`). If the user named a specific schedule, `_read` it first and surface a short summary (cron expression, timezone, target workerId, status, runCount, nextRunAt, lastRunAt).
2. **Identify the target** — `mcp__ai_builder__worker_search` or `mcp__ai_builder__workflow_search` for the workflow / worker the user wants to schedule. **Stop and hand off if it doesn't exist.** Do not build it inline.
3. **Plan the cron** — render a short markdown plan: name, target workerId, cron expression with a plain-English description, timezone (default UTC — confirm explicitly if the user implies a local timezone), `inputParams` JSON object passed to each run, optional start/end dates, optional `maxRuns` cap. Wait for explicit user approval before creating.
4. **Cron expression rules** —
   - Standard 5-part: `minute hour day month weekday` (e.g. `0 9 * * 1-5` = weekdays at 09:00).
   - Shorthand accepted: `@hourly`, `@daily`, `@weekly`, `@monthly`, `@yearly`.
   - Always state the cron in plain English next to the expression — it's the most common source of misunderstandings.
   - Default timezone is `UTC`. If the user says "9am every weekday" without specifying a timezone, ask which one.
5. **inputParams** — these are the same JSON params the user would pass to `worker_execute`. **Templated references to other nodes are not supported in scheduled runs** — inputParams must be fixed values. If the user implies dynamic input, push back and propose either (a) a wrapper worker that produces the dynamic input internally, or (b) a webhook instead of a schedule.
6. **Create / update / delete** —
   - `mcp__ai_builder__schedule_create` returns the new scheduleId. Schedule starts active by default unless `enabled: false` or `startDate` is in the future.
   - `mcp__ai_builder__schedule_update` for changes. Cron / startDate / endDate / timezone changes recalculate `nextRunAt`.
   - `mcp__ai_builder__schedule_toggle` pauses without deleting. Prefer this over delete for temporary holds.
   - `mcp__ai_builder__schedule_delete` is destructive — follow the playbook's guardrail: summarise impact, wait for explicit `confirm`, then act.
7. **Verify** — call `mcp__ai_builder__schedule_run_now` to trigger an immediate test execution outside the cron timetable. Surface the returned `taskId` and tell the user to check the queue UI for the manual run's result. The schedule's own `runCount` / `lastRunAt` are not affected by manual runs.
8. **Final report** — render a short markdown summary inline: schedule name, cron + plain English, target worker, next scheduled run, and a clickable link to the Everworker UI:
   `[<schedule name>](${user_config.everworker_url}/scheduler)`

Schedules are **server-side** — no on-disk sidecar discipline, and the PreToolUse hook does not gate `schedule_*` calls. Safety lives in the destructive-action guardrail above.

**Solution tags:** Schedules **do** support tags (the `tags` array). When the schedule is part of a multi-entity solution, pass `tags: ["solution:<slug>", ...]` to `schedule_create`. See PLAYBOOK § SOLUTION TAGS for the full rule.

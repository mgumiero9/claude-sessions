---
description: Cross-project Claude Code session index with cached LLM summaries. Deterministic table + cache; the model only summarizes what changed.
argument-hint: "[limit] [--by-size|-s | --by-mtime|-m]"
allowed-tools: Bash, Write, Agent
---

Your ONLY job is to write summaries for sessions whose transcript changed
since last time. Extraction, the cache, and the table are deterministic
scripts — never hand-render the table or hand-write the cache JSON (it is slow
and corrupts data). Do not narrate; just run the steps.

## Step 1 — what changed

```
zsh -f ~/.claude/scripts/claude-sessions-cache.zsh misses $ARGUMENTS
```

stderr prints `[X/Y cached, Z to summarize]`. stdout is one JSON object per
session that still needs a summary: `{id, mtime, project, prompts}`.

- **stdout empty** → nothing changed. Go straight to Step 4.
- otherwise → Step 2.

## Step 2 — summarize the misses

Style for every summary: 4–9 words, no trailing period, plain Title-style,
saying what the work was about; if the last prompts make the outcome clear,
add it after a semicolon. Match the prompts' dominant language (Portuguese
prompts → Portuguese summary). Ignore leftover noise (image tags, pasted
output).

Let Z = number of miss records.

- **Z ≤ 8** → write them yourself now.
- **Z > 8** → split the miss records into 4 contiguous groups and dispatch 4
  `Agent` calls **in one message** (concurrent), `subagent_type:
  "general-purpose"`, `model: "haiku"`. Give each agent only its group's
  records and the style above, and tell it: *Reply by writing the file
  `/tmp/.cs-sumN.json` (N = your group number) containing exactly
  `{"<id>":{"mtime":<mtime>,"summary":"<text>"}, ...}` — nothing else.* Assign
  each agent a distinct N (1..4).

For the inline (Z ≤ 8) path, use the **Write** tool to create
`/tmp/.cs-sum1.json` with the same `{"<id>":{"mtime":..,"summary":..}}` shape.

## Step 3 — fold summaries into the cache

```
zsh -f ~/.claude/scripts/claude-sessions-cache.zsh merge /tmp/.cs-sum*.json
```

## Step 4 — render (deterministic, this is the deliverable)

```
zsh -f ~/.claude/scripts/claude-sessions-cache.zsh render
```

That command prints the final table and the resume hint. Its output is shown
to the user as-is — do **not** reprint, reformat, or summarize it. Reply with
at most one short sentence (e.g. the `[X/Y cached…]` figure), or nothing.

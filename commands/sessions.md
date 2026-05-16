---
description: List Claude Code sessions across all projects with an LLM-written summary of what each one is about (cached, parallelized).
argument-hint: "[limit] [--by-size|-s | --by-mtime|-m]"
allowed-tools: Bash, Read, Write, Agent
---

You are generating a cross-project session index. The PREVIEW column must be a
human-readable summary of *what each session is about*. Do the cheap
extraction with the script, summarize only the cache misses (in parallel),
then print one clean table.

Speed matters: the only slow part is generating summaries, so minimize and
parallelize that work. Do NOT think out loud between steps — just execute.

## Step 1 — extract (cheap, deterministic)

Run, passing the user's args through verbatim (default limit 60):

```
zsh -f ~/.claude/scripts/claude-sessions-extract.zsh $ARGUMENTS
```

`zsh -f` is required. Each line is one JSON object:
`{id, mtime, size_h, when, project, branch, cached, summary, prompts}`

- `cached: true`  → `summary` is filled (sessions seen before, or ones with no
  readable prompts). Reuse `summary` verbatim. **Never re-summarize these.**
- `cached: false` → needs a summary; `prompts` has 5 first + 3 last real prompts.

If the only output is `{"error": ...}`, show it and stop. Keep the full NDJSON
(you need every row, in order, for the table).

## Step 2 — summarize the cache misses (parallel)

Collect the `cached: false` records. Let N be how many there are.

- **N == 0** → skip to Step 4.
- **N ≤ 12** → summarize them yourself, inline, now.
- **N > 12** → split them into 4 contiguous groups of roughly equal size and
  dispatch 4 `Agent` calls **in a single message** (so they run concurrently),
  `subagent_type: "general-purpose"`, `model: "haiku"`. Give each agent only
  its group's `{id, mtime, project, prompts}` records and this instruction:

  > For each record, write a `summary`: 4–9 words, no trailing period, plain
  > Title-style, saying what the work was about; if the last prompts make the
  > outcome clear, append it after a semicolon. Match the dominant language of
  > that session's prompts (Portuguese prompts → Portuguese summary). Ignore
  > leftover noise (image tags, pasted output). Reply with ONLY a compact JSON
  > object `{"<id>": {"mtime": <mtime>, "summary": "<text>"}, ...}` — no prose,
  > no code fence.

  Merge the JSON objects the agents return.

Apply the same summary style for the inline (N ≤ 12) path.

## Step 3 — persist the cache (next run is instant)

Only for sessions summarized in Step 2 (skip if none). Write the merged
`{ "<id>": { "mtime": <mtime>, "summary": "<text>" }, ... }` object to
`/tmp/.cs-new-summaries.json` with the Write tool, then:

```
jq -s '.[0] * .[1]' ~/.claude/.sessions-summary-cache.json /tmp/.cs-new-summaries.json \
  > /tmp/.cs-cache-merged.json && mv /tmp/.cs-cache-merged.json ~/.claude/.sessions-summary-cache.json
```

## Step 4 — print the table

Plain monospace code block (no markdown table), rows in the script's original
order, columns and widths:

```
MODIFIED          SIZE   SESSION                               PROJECT             BRANCH                PREVIEW
----------------  -----  ------------------------------------  ------------------  --------------------  --------------------------------------------
<when>            <size> <full id>                             <project>           <branch>              <summary>
```

`PROJECT`/`BRANCH` truncated to column width with `…` if longer; `SESSION` is
the full id (needed to resume); `PREVIEW` is the summary (cached or fresh).

After the table, exactly one line:

`Resume any session from a terminal with:  claude-resume <session-id-prefix>`

Keep prose around the table to a minimum — the table is the deliverable.

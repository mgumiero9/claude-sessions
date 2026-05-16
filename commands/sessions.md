---
description: List Claude Code sessions across all projects with an LLM-written summary of what each one is about (cached).
argument-hint: "[limit] [--by-size|-s | --by-mtime|-m]"
allowed-tools: Bash, Read, Write
---

You are generating a cross-project session index. The PREVIEW column must be a
human-readable summary of *what each session is about* — not raw prompt
fragments. Do the cheap extraction with the script, summarize only what isn't
cached, then print one clean table.

## Step 1 — extract (deterministic, cheap)

Run, passing the user's arguments through verbatim (default limit is 60):

```
zsh -f ~/.claude/scripts/claude-sessions-extract.zsh $ARGUMENTS
```

`zsh -f` is required (skips the user's zshenv, which can inject a stdout
logger). The script prints one JSON object per line:

`{id, mtime, size_h, when, project, branch, cached, summary, prompts}`

- `cached: true`  → `summary` is already filled (reuse it verbatim, do NOT re-summarize).
- `cached: false` → `summary` is null; `prompts` holds 5 first + 3 last real user prompts.

If the output is a single `{"error": ...}` object, show that message and stop.

## Step 2 — summarize the cache misses

For every record with `cached: false`, write a `summary`:

- 4–9 words, no trailing period, Title-style but plain.
- Say what the work was *about*; if the last prompts make the outcome clear,
  append it after a semicolon (e.g. `Fix iOS build; ended on Apple ID signing`).
- Match the dominant language of that session's prompts (Portuguese → write in
  Portuguese, English → English).
- Ignore leftover noise (image tags, pasted output). If prompts are
  `["(no user message)"]`, use the summary `(no readable prompts)`.

Do this from the data already in front of you — do not re-read the JSONL files.

## Step 3 — persist the cache (so next run is instant)

Build a JSON object of ONLY the sessions you just summarized in this form:

`{ "<id>": { "mtime": <mtime>, "summary": "<your summary>" }, ... }`

Write it to `/tmp/.cs-new-summaries.json` (use the Write tool), then merge it
into the cache, newest winning:

```
jq -s '.[0] * .[1]' ~/.claude/.sessions-summary-cache.json /tmp/.cs-new-summaries.json \
  > /tmp/.cs-cache-merged.json && mv /tmp/.cs-cache-merged.json ~/.claude/.sessions-summary-cache.json
```

Skip Step 3 entirely if every record was already `cached: true`.

## Step 4 — print the table

Output as a plain monospace code block (no markdown table), columns in this
order and these widths, rows in the same order the script emitted them:

```
MODIFIED          SIZE   SESSION                               PROJECT             BRANCH                PREVIEW
----------------  -----  ------------------------------------  ------------------  --------------------  --------------------------------------------
<when>            <size> <id>                                  <project>           <branch>              <summary>
```

- `MODIFIED` = `when`, `SIZE` = `size_h`, `SESSION` = full `id` (needed to resume),
  `PROJECT`/`BRANCH` truncated to their column width with `…` if longer,
  `PREVIEW` = the summary (cached or freshly written).

After the table, print one line:

`Resume any session from a terminal with:  claude-resume <session-id-prefix>`

Be concise in prose around the table — the table is the deliverable.

# claude-sessions

A cross-project index of every [Claude Code](https://claude.com/claude-code)
session on your machine — with an **LLM-written summary of what each session is
about** in the PREVIEW column, not raw prompt fragments.

It ships as a Claude Code **slash command** (`/sessions`) plus a small shell
helper (`claude-resume`) for jumping back into a session from your terminal.

## Why?

Claude Code's built-in `/resume` only shows sessions for the project you
launched it from. Switch repos a lot and you lose track of in-progress work
elsewhere. The earlier version of this tool listed sessions with the first few
user prompts truncated to ~25 chars each — but real first prompts are mostly
noise (pasted terminal output, `[Image: source: …]`, "ok", "sim pf"), so you
still couldn't tell what a session was *about*.

`/sessions` fixes that: a script does the cheap extraction, then Claude itself
writes a one-line summary per session. Summaries are **cached per session**
(keyed by file mtime), so only sessions that actually changed get
re-summarized — the second run is effectively instant.

## Demo

Inside any Claude Code session:

```text
> /sessions 20

MODIFIED          SIZE   SESSION                               PROJECT          BRANCH                PREVIEW
----------------  -----  ------------------------------------  ---------------  --------------------  --------------------------------------------
2026-05-13 17:06  6.4M   6501bbeb-1444-4a40-95b8-3479697b83b7  plantao-app      main                  Fix iOS/Flutter build; ended on Apple ID signing
2026-05-13 17:08  2.8M   09c7d703-ccd7-45c9-b607-decc1643754e  plantao-backend  bugfix/P24H-17-ci-…   Stabilize CI: brakeman/rubocop on PR #13
2026-05-13 16:10  2.8M   8e157abf-c082-47d1-865c-01466ebf0742  plantao-app      main                  Onboard new dev: SMS verification walkthrough
...

Resume any session from a terminal with:  claude-resume <session-id-prefix>
```

Then, from your shell:

```text
$ claude-resume 09c7d703
→ cd /Users/me/Developer/plantao24h/repos/plantao-backend
→ claude --resume 09c7d703-ccd7-45c9-b607-decc1643754e
```

### Columns

- **MODIFIED / SIZE** — when and how big the transcript is on disk.
- **SESSION** — full UUID, ready for `claude-resume` (a prefix works too).
- **PROJECT** — basename of the directory Claude Code ran in. Pair it with
  BRANCH + SESSION to disambiguate sessions in the same repo.
- **BRANCH** — the last `gitBranch` recorded (the branch you stopped on).
- **PREVIEW** — an LLM summary of what the session is about, written from the
  first 5 + last 3 *real* user prompts (slash-commands, hooks, pasted terminal
  output, bare image tags and pure acknowledgements are filtered out before the
  model ever sees them). Cached per session.

## Requirements

- **zsh** (default shell on macOS since Catalina)
- **[jq](https://jqlang.github.io/jq/)** — `brew install jq` / `apt install jq`
- **Claude Code** (the `/sessions` command runs inside it)

Standard utilities used: `find`, `stat`, `date`, `head`, `tail`. macOS + Linux.

## Install

```bash
# Clone somewhere stable
git clone https://github.com/mgumiero9/claude-sessions.git ~/.local/share/claude-sessions

# 1. The helper scripts — used by the /sessions slash command
mkdir -p ~/.claude/scripts ~/.claude/commands
cp ~/.local/share/claude-sessions/claude-sessions-extract.zsh ~/.claude/scripts/
cp ~/.local/share/claude-sessions/claude-sessions-cache.zsh   ~/.claude/scripts/
cp ~/.local/share/claude-sessions/commands/sessions.md         ~/.claude/commands/

# 2. The shell helper (claude-resume) — source from ~/.zshrc
echo 'source ~/.local/share/claude-sessions/claude-sessions.zsh' >> ~/.zshrc
source ~/.zshrc
```

`/sessions` then works from any Claude Code session on the machine.

## Usage

```text
/sessions                     # 60 biggest sessions, summarized (cached)
/sessions 100                 # 100 biggest
/sessions --by-mtime          # sort by most-recently-modified instead
/sessions 20 -m               # 20 most recently modified
```

```bash
claude-resume <session-id>    # cd into the right project and resume
claude-resume 09c7d703        # id prefix is fine (first 8 chars usually unique)
```

Default sort is transcript file size (largest first, limit 60) — it surfaces
your longest / most substantial sessions, usually the ones worth resuming or
pruning. `--by-mtime` (`-m`) switches to "what did I touch most recently?".

## Resuming a session

Claude Code's `--resume` is project-scoped: it only knows sessions under the
encoded folder for your current directory. `claude-resume` reads the original
`cwd` from the session's JSONL, `cd`s there, and runs `claude --resume
<full-id>`. By hand:

```bash
cd /path/to/the/project
claude --resume <session-id>
```

## How it works

Claude Code stores transcripts at
`~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl` (the absolute
project path with `/` → `-`).

The model only ever writes summaries for sessions that changed. Everything
else — extraction, caching, and **rendering the table** — is deterministic
shell, because an LLM hand-rendering a 50-row table is slow and corrupts
ids/summaries.

1. `claude-sessions-extract.zsh` walks every `.jsonl`, sorts by size (or
   mtime), and per session extracts the first 5 + last 3 real user prompts,
   dropping the noise. Sessions with no readable prompts get a deterministic
   summary on the spot.
2. `claude-sessions-cache.zsh misses` runs the extractor (with `zsh -f`, since
   a user's zshenv can inject a stdout logger), stashes the full NDJSON, and
   prints **only** the sessions whose mtime no longer matches
   `~/.claude/.sessions-summary-cache.json`. It also prints
   `[X/Y cached, Z to summarize]` so you can see the cache working.
3. `/sessions` summarizes just those Z misses — inline if few, or fanned out
   across 4 parallel Haiku subagents if many — each writing a small JSON chunk.
4. `claude-sessions-cache.zsh merge` folds the chunks into the cache.
5. `claude-sessions-cache.zsh render` prints the final aligned table straight
   from the stash + cache. No model involvement; that stdout is the output you
   see.

A warm run (nothing changed) skips steps 3–4 entirely: two quick shell calls,
no model generation, effectively instant.

## Notes

### zsh footguns (both of these bit us)

- `$path` / `$fpath` are special zsh arrays tied to `$PATH` / the function
  search path. The file-path variable is named `fpath_` on purpose — don't
  rename it back.
- `local` at **script top level** (outside any function) *prints*
  `name=value` for an already-set variable. That's why all of
  `claude-sessions-extract.zsh` lives inside a function — running it as a plain
  script otherwise pollutes the NDJSON on stdout.

### Bash support

Uses zsh-specific features (`${var:h:t}`, native arrays, glob qualifiers).
Bash users can install zsh just to run it, or port it — PRs welcome.

## License

[MIT](LICENSE)

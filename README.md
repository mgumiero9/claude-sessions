# claude-sessions

A tiny zsh function that lists every [Claude Code](https://claude.com/claude-code) session across all projects on your machine, sorted by most recent, with a preview of each session's first user prompt.

## Why?

Claude Code's built-in `/resume` only shows sessions for the project you launched it from. If you switch between repos a lot, you lose visibility into in-progress sessions in other projects. `claude-sessions` gives you a single global view.

## Demo

```text
$ claude-sessions
MODIFIED                 SIZE  SESSION                               PROJECT                           BRANCH                      PREVIEW
-------------------  --------  ------------------------------------  --------------------------------  --------------------------  -------
2026-05-11 10:31:25    290.4K  dc3fdfbd-e5b1-4dd6-af66-b00ef76ae6da  /Users/me/Developer/foo/backend   P24H-16-sms-validation...   help me with this: SSH key
2026-05-11 09:57:03    324.1K  c2ee22e2-4d8d-4c9d-bbe4-0155e2c8d55d  /Users/me/Developer/foo/backend   main                        por favor veja se faz sentido...
2026-05-08 11:31:23    112.8K  2bfae921-5520-476f-8169-fa5f9820c332  /Users/me/Developer/bar/demo1     main                        what's in this project?
...

$ claude-resume dc3fdfbd
→ cd /Users/me/Developer/foo/backend
→ claude --resume dc3fdfbd-e5b1-4dd6-af66-b00ef76ae6da
```

## Requirements

- **zsh** (default shell on macOS since Catalina)
- **[jq](https://jqlang.github.io/jq/)** — `brew install jq` on macOS, `apt install jq` on Debian/Ubuntu

Standard utilities used: `find`, `stat`, `date`, `grep`, `head`, `tr`, `cut`. Works on macOS and Linux.

## Install

```bash
# Clone somewhere stable
git clone https://github.com/mgumiero9/claude-sessions.git ~/.local/share/claude-sessions

# Source it from your ~/.zshrc
echo 'source ~/.local/share/claude-sessions/claude-sessions.zsh' >> ~/.zshrc

# Reload
source ~/.zshrc
```

Or just copy the contents of `claude-sessions.zsh` straight into your `~/.zshrc`.

## Usage

```bash
claude-sessions               # 20 most recent sessions (sorted by mtime DESC)
claude-sessions 50            # 50 most recent sessions

claude-sessions --by-size     # sort by transcript file size DESC instead of mtime
claude-sessions 50 -s         # 50 biggest sessions on disk

claude-resume <session-id>    # cd into the right project and resume
claude-resume dc3fdfbd        # session-id prefix is fine (first 8 chars usually unique)
```

The default sort is by modification time (newest first), which answers "what was I working on most recently?". The `--by-size` flag (alias `-s`) sorts by transcript size descending, which is useful for spotting your largest / longest-running sessions — typically the ones eating disk or worth pruning.

## Resuming a session

Claude Code's `--resume` is project-scoped: it only knows about sessions stored under the encoded folder for your current working directory. `claude-resume` reads the original `cwd` recorded in the session's JSONL, `cd`s there for you, and runs `claude --resume <full-id>`.

If you'd rather do it by hand:

```bash
cd /path/to/the/project
claude --resume <session-id>
```

## How it works

Claude Code stores session transcripts at:

```
~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl
```

where `<encoded-project-path>` is the absolute project path with `/` replaced by `-`.

The function:

1. Walks `~/.claude/projects/*/` and finds every `.jsonl` file.
2. Sorts by mtime (newest first).
3. Uses `jq` to pull out the first real user prompt from each transcript (skipping slash-command messages, hooks, and system reminders).
4. Prints a compact table.

## Notes

### zsh footgun

In zsh, `$path` (lowercase) is a special array tied to `$PATH`, and `$fpath` mirrors the function search path. Assigning to either inside a function silently breaks command lookup. If you fork this, **don't rename the `fpath_` variable back to `path`** — that's why it has the trailing underscore.

### Bash support

The function uses a few zsh-specific features (`${var:h:t}` path modifiers, native arrays). Bash users can install zsh just to run it, or port it — PRs welcome.

## License

[MIT](LICENSE)

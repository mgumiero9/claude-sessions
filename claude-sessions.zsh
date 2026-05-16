#!/usr/bin/env zsh
# claude-resume   — resume a specific session by id (or prefix) from anywhere.
#
# NOTE: the cross-project *listing* moved into Claude Code itself, as the
# `/sessions` slash command (~/.claude/commands/sessions.md). It uses the LLM
# to write a real "what is this session about" summary per row (cached), which
# the old fixed-width prompt-fragment listing could never do well.
# `claude-sessions` here is now just a pointer to it; `claude-resume` stays —
# resuming has to run in your shell (it cd's and execs `claude`).
#
# Claude Code (Anthropic's CLI) stores session transcripts as JSONL files at:
#   ~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl
# Each project lives in its own folder, so the built-in /resume only shows
# sessions for the project you launched Claude Code from. These functions
# give you a global view across every project on the machine, and let you
# jump straight back into any session without manually cd'ing first.
#
# Usage:
#   /sessions                     # (inside Claude Code) summarized listing
#   /sessions 100 --by-mtime      # 100 most-recently-modified, summarized
#   claude-resume <session-id>    # cd into the right project and resume
#   claude-resume dc3fdfbd        # prefix match (first unique match wins)
#
# Requirements:
#   - zsh
#   - jq        (macOS: `brew install jq` · Debian/Ubuntu: `apt install jq`)
#   - Standard POSIX utilities: find, stat, date, grep, head, tail, tr, cut
#
# Footgun note:
#   In zsh, $path (lowercase) is a special array mirroring $PATH, and $fpath
#   is the function search path. Don't name local variables `path` or `fpath`
#   inside shell functions — assigning to them silently breaks command lookup.
#   That's why the file-path variable below is named `fpath_`.
#
# License: MIT

claude-sessions() {
    emulate -L zsh
    cat <<'MSG'
The summarized cross-project listing now lives inside Claude Code:

    /sessions [limit] [--by-size|-s | --by-mtime|-m]

It writes an LLM summary of what each session is about (cached per session),
which the old prompt-fragment table couldn't do. Run it from any Claude Code
session. To jump back into a session from this shell, use:

    claude-resume <session-id-or-prefix>
MSG
}

claude-resume() {
    emulate -L zsh
    setopt local_options null_glob
    local sid=$1
    if [[ -z $sid ]]; then
        echo "Usage: claude-resume <session-id-or-prefix>"
        return 1
    fi
    local dir="$HOME/.claude/projects"
    [[ -d $dir ]] || { echo "No Claude projects dir at $dir"; return 1; }

    local -a matches
    matches=( "${dir}"/*/"${sid}"*.jsonl )
    if (( ${#matches} == 0 )); then
        echo "No session matching '$sid' found under $dir"
        return 1
    fi
    if (( ${#matches} > 1 )); then
        echo "Multiple sessions match '$sid':"
        printf '  %s\n' "${matches[@]}"
        echo "Try a longer prefix."
        return 1
    fi
    local fpath_=${matches[1]}
    local full_sid=${fpath_:t:r}
    local cwd
    cwd=$(jq -r 'select(.cwd != null) | .cwd' "$fpath_" 2>/dev/null | head -n1)
    if [[ -z $cwd ]]; then
        echo "Could not read cwd from $fpath_"
        return 1
    fi
    if [[ ! -d $cwd ]]; then
        echo "Project directory recorded in the session no longer exists:"
        echo "  $cwd"
        return 1
    fi
    echo "→ cd $cwd"
    echo "→ claude --resume $full_sid"
    cd "$cwd" && claude --resume "$full_sid"
}

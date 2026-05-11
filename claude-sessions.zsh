#!/usr/bin/env zsh
# claude-sessions — list Claude Code sessions across all projects, newest first.
#
# Claude Code (Anthropic's CLI) stores session transcripts as JSONL files at:
#   ~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl
# Each project lives in its own folder, so the built-in /resume only shows
# sessions for the project you launched Claude Code from. This function gives
# you a global view across every project on the machine, with a preview of each
# session's first real user prompt.
#
# Usage:
#   claude-sessions          # 20 most recent sessions
#   claude-sessions 50       # 50 most recent sessions
#
# Requirements:
#   - zsh
#   - jq        (macOS: `brew install jq` · Debian/Ubuntu: `apt install jq`)
#   - Standard POSIX utilities: find, stat, date, grep, head, tr, cut
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
    local limit=${1:-20}
    local dir="$HOME/.claude/projects"
    [[ -d $dir ]] || { echo "No Claude projects dir at $dir"; return 1; }

    # macOS (BSD) and Linux (GNU) disagree on `stat` and `date` flags.
    local -a stat_fmt
    local is_macos=0
    if [[ "$(uname)" == "Darwin" ]]; then
        is_macos=1
        stat_fmt=(-f '%m %z %N')
    else
        stat_fmt=(-c '%Y %s %n')
    fi

    printf '%-19s  %8s  %-36s  %-38s  %s\n' "MODIFIED" "SIZE" "SESSION" "PROJECT" "PREVIEW"
    printf '%-19s  %8s  %-36s  %-38s  %s\n' "-------------------" "--------" "------------------------------------" "--------------------------------------" "-------"

    local line mtime rest size fpath_ proj sess when human decoded short_proj preview
    while IFS= read -r line; do
        mtime=${line%% *}; rest=${line#* }
        size=${rest%% *}; fpath_=${rest#* }
        proj=${fpath_:h:t}
        sess=${fpath_:t:r}
        if (( is_macos )); then
            when=$(date -r "$mtime" '+%Y-%m-%d %H:%M:%S')
        else
            when=$(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S')
        fi
        if   (( size >= 1048576 )); then human=$(printf '%.1fM' $((size / 1048576.0)))
        elif (( size >= 1024 ));    then human=$(printf '%.1fK' $((size / 1024.0)))
        else human="${size}B"
        fi
        decoded=${proj//-//}
        short_proj=$decoded
        (( ${#short_proj} > 36 )) && short_proj="...${short_proj: -33}"
        preview=$(jq -r 'select(.type=="user") | .message.content |
            if type=="string" then .
            else (map(select(.type=="text") | .text // "") | join(" "))
            end' "$fpath_" 2>/dev/null \
            | grep -vE '^\s*(<command-|<local-command|Caveat:|<system-reminder|$)' \
            | head -n1 \
            | tr '\n\t' '  ' \
            | cut -c 1-80)
        [[ -z $preview ]] && preview="(no user message)"
        printf '%-19s  %8s  %-36s  %-38s  %s\n' "$when" "$human" "$sess" "$short_proj" "$preview"
    done < <(find "$dir" -maxdepth 2 -name '*.jsonl' -type f -print0 \
              | xargs -0 stat "${stat_fmt[@]}" 2>/dev/null \
              | sort -rn \
              | head -n "$limit")
}

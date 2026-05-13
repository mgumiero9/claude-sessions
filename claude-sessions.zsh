#!/usr/bin/env zsh
# claude-sessions — list Claude Code sessions across all projects, newest first.
# claude-resume   — resume a specific session by id (or prefix) from anywhere.
#
# Claude Code (Anthropic's CLI) stores session transcripts as JSONL files at:
#   ~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl
# Each project lives in its own folder, so the built-in /resume only shows
# sessions for the project you launched Claude Code from. These functions
# give you a global view across every project on the machine, and let you
# jump straight back into any session without manually cd'ing first.
#
# Usage:
#   claude-sessions               # 20 most recent sessions
#   claude-sessions 50            # 50 most recent sessions
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

    printf '%-19s  %8s  %-36s  %-32s  %-26s  %s\n' \
        "MODIFIED" "SIZE" "SESSION" "PROJECT" "BRANCH" "PREVIEW"
    printf '%-19s  %8s  %-36s  %-32s  %-26s  %s\n' \
        "-------------------" "--------" \
        "------------------------------------" \
        "--------------------------------" \
        "--------------------------" "-------"

    local line mtime rest size fpath_ proj sess when human \
          cwd branch short_proj short_branch preview
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

        # Real cwd (from the JSONL itself) — more accurate than decoding the folder name,
        # since directory names containing '-' can't be losslessly reversed from '/'-encoding.
        cwd=$(jq -r 'select(.cwd != null) | .cwd' "$fpath_" 2>/dev/null | head -n1)
        [[ -z $cwd ]] && cwd=${proj//-//}
        short_proj=$cwd
        (( ${#short_proj} > 32 )) && short_proj="...${short_proj: -29}"

        # Last gitBranch wins (reflects state at end of session, not start).
        branch=$(jq -r 'select(.gitBranch != null) | .gitBranch' "$fpath_" 2>/dev/null | tail -n1)
        [[ -z $branch ]] && branch="(none)"
        short_branch=$branch
        (( ${#short_branch} > 26 )) && short_branch="${short_branch:0:23}..."

        preview=$(jq -r 'select(.type=="user") | .message.content |
            if type=="string" then .
            else (map(select(.type=="text") | .text // "") | join(" "))
            end' "$fpath_" 2>/dev/null \
            | grep -vE '^\s*(<command-|<local-command|Caveat:|<system-reminder|$)' \
            | head -n1 \
            | tr '\n\t' '  ' \
            | cut -c 1-60)
        [[ -z $preview ]] && preview="(no user message)"

        printf '%-19s  %8s  %-36s  %-32s  %-26s  %s\n' \
            "$when" "$human" "$sess" "$short_proj" "$short_branch" "$preview"
    done < <(find "$dir" -maxdepth 2 -name '*.jsonl' -type f -print0 \
              | xargs -0 stat "${stat_fmt[@]}" 2>/dev/null \
              | sort -rn \
              | head -n "$limit")
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

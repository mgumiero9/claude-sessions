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
#   claude-sessions               # 60 biggest sessions (sorted by file size DESC)
#   claude-sessions 100           # 100 biggest sessions
#   claude-sessions --by-mtime    # sort by modification time DESC instead
#   claude-sessions 20 -m         # 20 most recently modified sessions
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
    local limit=60
    local by_size=1
    while (( $# )); do
        case $1 in
            --by-size|-s)  by_size=1; shift ;;
            --by-mtime|-m) by_size=0; shift ;;
            --help|-h)
                echo "Usage: claude-sessions [limit] [--by-size|-s | --by-mtime|-m]"
                echo "Defaults: 60 sessions, sorted by file size DESC."
                return 0 ;;
            -*) echo "Unknown flag: $1"; return 1 ;;
            *)
                if [[ $1 == <-> ]]; then
                    limit=$1; shift
                else
                    echo "Bad argument: $1"; return 1
                fi ;;
        esac
    done
    local dir="$HOME/.claude/projects"
    [[ -d $dir ]] || { echo "No Claude projects dir at $dir"; return 1; }
    local sort_key
    if (( by_size )); then sort_key="-k2,2"
    else sort_key="-k1,1"
    fi

    # macOS (BSD) and Linux (GNU) disagree on `stat` and `date` flags.
    local -a stat_fmt
    local is_macos=0
    if [[ "$(uname)" == "Darwin" ]]; then
        is_macos=1
        stat_fmt=(-f '%m %z %N')
    else
        stat_fmt=(-c '%Y %s %n')
    fi

    printf '%-19s  %8s  %-36s  %-20s  %-26s  %s\n' \
        "MODIFIED" "SIZE" "SESSION" "PROJECT" "BRANCH" "PREVIEW (first 3 user prompts)"
    printf '%-19s  %8s  %-36s  %-20s  %-26s  %s\n' \
        "-------------------" "--------" \
        "------------------------------------" \
        "--------------------" \
        "--------------------------" "------------------------------"

    local line mtime rest size fpath_ proj sess when human \
          cwd branch short_proj short_branch preview p
    local -a prompts parts
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
        # Project column shows just the basename (e.g. plantao-backend) — pair it with the
        # SESSION id and BRANCH to disambiguate.
        cwd=$(jq -r 'select(.cwd != null) | .cwd' "$fpath_" 2>/dev/null | head -n1)
        [[ -z $cwd ]] && cwd=${proj//-//}
        short_proj=${cwd:t}
        [[ -z $short_proj ]] && short_proj="(unknown)"
        (( ${#short_proj} > 20 )) && short_proj="${short_proj:0:17}..."

        # Last gitBranch wins (reflects state at end of session, not start).
        branch=$(jq -r 'select(.gitBranch != null) | .gitBranch' "$fpath_" 2>/dev/null | tail -n1)
        [[ -z $branch ]] && branch="(none)"
        short_branch=$branch
        (( ${#short_branch} > 26 )) && short_branch="${short_branch:0:23}..."

        # First 3 real user prompts. "Real" = skip slash-commands, hooks,
        # caveat banners, and system-reminder blobs. Joined by →, each capped at ~25 chars
        # so the column stays around 80.
        # Note: gsub() inside jq flattens any newlines *within* a single prompt to spaces,
        # so jq's `-r` output is guaranteed to be exactly one line per prompt. Doing this
        # with `tr` after the pipe would also flatten the line breaks *between* prompts
        # and collapse the three into one.
        prompts=("${(@f)$(jq -r '
            select(.type=="user") | .message.content |
            (if type=="string" then .
             else (map(select(.type=="text") | .text // "") | join(" "))
             end) | gsub("[\\n\\r\\t]+"; " ")
            ' "$fpath_" 2>/dev/null \
            | grep -vE '^\s*(<command-|<local-command|Caveat:|<system-reminder|$)' \
            | head -n3)}")
        if (( ${#prompts} == 0 )); then
            preview="(no user message)"
        else
            parts=()
            for p in $prompts; do
                [[ -z $p ]] && continue
                parts+=( "$(printf '%s' "$p" | cut -c 1-25)" )
            done
            preview=${(j: → :)parts}
        fi

        printf '%-19s  %8s  %-36s  %-20s  %-26s  %s\n' \
            "$when" "$human" "$sess" "$short_proj" "$short_branch" "$preview"
    done < <(find "$dir" -maxdepth 2 -name '*.jsonl' -type f -print0 \
              | xargs -0 stat "${stat_fmt[@]}" 2>/dev/null \
              | sort $sort_key -rn \
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

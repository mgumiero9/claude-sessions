#!/usr/bin/env zsh
# claude-sessions-extract — feed the /sessions slash command.
#
# Emits one NDJSON record per Claude Code session, newest/biggest first.
# It does the cheap, deterministic work (find + jq + noise filtering + cache
# lookup) so the LLM side of /sessions only has to summarize the few sessions
# whose transcript actually changed.
#
# Output record shape (one JSON object per line):
#   { "id", "mtime", "size_h", "when", "project", "branch",
#     "cached": <bool>,
#     "summary": <string|null>,     # set when cached==true
#     "prompts": [<string>, ...] }   # set when cached==false (needs summarizing)
#
# Cache file (read here, rewritten by the slash command after summarizing):
#   ~/.claude/.sessions-summary-cache.json
#     { "<session-id>": { "mtime": <int>, "summary": "<string>" } }
#
# Usage:
#   zsh -f claude-sessions-extract.zsh [limit] [--by-size|-s | --by-mtime|-m]
# Defaults: 60 sessions, sorted by file size DESC.
#
# Requirements: zsh, jq, find, stat, date.
#
# Footguns (both real, both bit us):
#   * In zsh, $path/$fpath are special arrays. The file-path var is fpath_.
#   * `local` at *script top level* (outside any function) PRINTS `name=value`
#     for an already-set variable. So all logic lives inside a function.

_cse_main() {
    emulate -L zsh
    setopt local_options pipefail
    # Defensive: some user zshenv setups inject a DEBUG trap / command-logger
    # that would pollute stdout. The slash command also runs us with `zsh -f`.
    unsetopt xtrace verbose 2>/dev/null
    trap - DEBUG 2>/dev/null
    unfunction TRAPDEBUG 2>/dev/null

    local limit=60
    local by_size=1
    while (( $# )); do
        case $1 in
            --by-size|-s)  by_size=1; shift ;;
            --by-mtime|-m) by_size=0; shift ;;
            --help|-h)
                print -r -- "Usage: claude-sessions-extract [limit] [--by-size|-s | --by-mtime|-m]"
                return 0 ;;
            -*) print -r -- "Unknown flag: $1" >&2; return 1 ;;
            *)
                if [[ $1 == <-> ]]; then limit=$1; shift
                else print -r -- "Bad argument: $1" >&2; return 1
                fi ;;
        esac
    done

    local dir="$HOME/.claude/projects"
    [[ -d $dir ]] || { print -r -- "{\"error\":\"No Claude projects dir at $dir\"}"; return 1; }

    local cache="$HOME/.claude/.sessions-summary-cache.json"
    [[ -f $cache ]] || print -r -- '{}' > "$cache"

    local sort_key
    if (( by_size )); then sort_key="-k2,2"; else sort_key="-k1,1"; fi

    local -a stat_fmt
    local is_macos=0
    if [[ "$(uname)" == "Darwin" ]]; then
        is_macos=1; stat_fmt=(-f '%m %z %N')
    else
        stat_fmt=(-c '%Y %s %n')
    fi

    local line mtime rest size fpath_ proj sess when human cwd branch \
          short_proj cached_mtime cached_summary pr lc t jarr
    local -a prompts head_p tail_p last3 final_prompts

    while IFS= read -r line; do
        mtime=${line%% *}; rest=${line#* }
        size=${rest%% *}; fpath_=${rest#* }
        proj=${fpath_:h:t}
        sess=${fpath_:t:r}

        if (( is_macos )); then
            when=$(date -r "$mtime" '+%Y-%m-%d %H:%M')
        else
            when=$(date -d "@$mtime" '+%Y-%m-%d %H:%M')
        fi
        if   (( size >= 1048576 )); then human=$(printf '%.1fM' $((size / 1048576.0)))
        elif (( size >= 1024 ));    then human=$(printf '%.1fK' $((size / 1024.0)))
        else human="${size}B"
        fi

        cwd=$(jq -r 'select(.cwd != null) | .cwd' "$fpath_" 2>/dev/null | head -n1)
        [[ -z $cwd ]] && cwd=${proj//-//}
        short_proj=${cwd:t}
        [[ -z $short_proj ]] && short_proj="(unknown)"

        branch=$(jq -r 'select(.gitBranch != null) | .gitBranch' "$fpath_" 2>/dev/null | tail -n1)
        [[ -z $branch ]] && branch="(none)"

        # Cache hit? Same session id AND same mtime → reuse stored summary.
        cached_mtime=$(jq -r --arg id "$sess" '.[$id].mtime // empty' "$cache" 2>/dev/null)
        if [[ -n $cached_mtime && $cached_mtime == $mtime ]]; then
            cached_summary=$(jq -r --arg id "$sess" '.[$id].summary // empty' "$cache" 2>/dev/null)
            if [[ -n $cached_summary ]]; then
                jq -cn --arg id "$sess" --argjson mt "$mtime" --arg sh "$human" \
                       --arg w "$when" --arg pj "$short_proj" --arg br "$branch" \
                       --arg sm "$cached_summary" \
                    '{id:$id,mtime:$mt,size_h:$sh,when:$w,project:$pj,branch:$br,cached:true,summary:$sm,prompts:[]}'
                continue
            fi
        fi

        # Cache miss → extract real user prompts, drop the noise.
        # Noise = slash-command/hook/system blobs, pasted terminal output,
        # bare image refs, interruptions, pure acknowledgements.
        prompts=("${(@f)$(jq -r '
            select(.type=="user") | .message.content |
            (if type=="string" then .
             else (map(select(.type=="text") | .text // "") | join(" "))
             end) | gsub("[\\n\\r\\t]+"; " ") | gsub("^ +| +$"; "")
            ' "$fpath_" 2>/dev/null)}")

        head_p=(); tail_p=()
        for pr in $prompts; do
            [[ -z ${pr// } ]] && continue
            # structural / tool noise
            [[ $pr == '<command-'* || $pr == '<local-command'* || $pr == '<bash-input'* \
               || $pr == '<bash-stdout'* || $pr == '<system-reminder'* \
               || $pr == 'Caveat:'* || $pr == '[Request interrupted'* ]] && continue
            # Claude Code auto-resume / continuation system messages
            [[ $pr == 'Continue from where you left off'* \
               || $pr == 'This session is being continued'* \
               || $pr == 'Please continue'* ]] && continue
            # bare image reference (whole message is just an image tag)
            [[ $pr == '[Image #'*']' || $pr == '[Image: source:'* ]] && continue
            # pasted terminal output (oh-my-zsh arrow / git-prompt segment)
            [[ $pr == $'➔'* || $pr == $'➤'* || $pr == *'git:('* ]] && continue
            # pure acknowledgements / fillers
            lc=${(L)pr}
            [[ $lc == (ok|okay|sim|sim pf|sim, pf|yes|yep|yes please|yes pls|thanks|thank you|obrigado|obg|great|perfect|nice|good|not good...|continue|vai|go|next|ok pf|beleza|blz)(.|\!|\?|)## ]] && continue
            # too short to carry intent
            (( ${#${pr// /}} < 12 )) && continue
            (( ${#head_p} < 5 )) && head_p+=("${pr[1,240]}")
            tail_p+=("${pr[1,240]}")
        done

        # last 3 meaningful prompts, minus any already in the head slice
        last3=()
        (( ${#tail_p} > ${#head_p} )) && last3=(${tail_p[-3,-1]})
        final_prompts=($head_p)
        for t in $last3; do
            [[ ${final_prompts[(Ie)$t]} -eq 0 ]] && final_prompts+=("$t")
        done

        if (( ${#final_prompts} == 0 )); then
            jq -cn --arg id "$sess" --argjson mt "$mtime" --arg sh "$human" \
                   --arg w "$when" --arg pj "$short_proj" --arg br "$branch" \
                '{id:$id,mtime:$mt,size_h:$sh,when:$w,project:$pj,branch:$br,cached:false,summary:null,prompts:["(no user message)"]}'
        else
            jarr=$(printf '%s\n' "${final_prompts[@]}" | jq -R . | jq -cs .)
            jq -cn --arg id "$sess" --argjson mt "$mtime" --arg sh "$human" \
                   --arg w "$when" --arg pj "$short_proj" --arg br "$branch" \
                   --argjson pr "$jarr" \
                '{id:$id,mtime:$mt,size_h:$sh,when:$w,project:$pj,branch:$br,cached:false,summary:null,prompts:$pr}'
        fi
    done < <(find "$dir" -maxdepth 2 -name '*.jsonl' -type f -print0 \
              | xargs -0 stat "${stat_fmt[@]}" 2>/dev/null \
              | sort $sort_key -rn \
              | head -n "$limit")
}

_cse_main "$@"

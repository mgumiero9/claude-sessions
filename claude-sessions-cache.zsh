#!/usr/bin/env zsh
# claude-sessions-cache — deterministic orchestration for the /sessions command.
#
# The LLM is slow and unreliable at two things it was doing before:
#   * hand-rendering a 50-row aligned table (slow + it corrupted ids/summaries)
#   * serializing a 50-line JSON cache file (slow + it errored and retried)
# Both are pure data plumbing. This script does them so the model only ever
# has to write the few summaries that actually changed.
#
# Subcommands:
#   misses [extract-args...]
#       Run the extractor, stash the full NDJSON at $STASH, and print ONLY the
#       records that still need an LLM summary (cached==false), one per line:
#         {id, mtime, project, prompts}
#       Prints nothing if everything is cached → caller skips straight to render.
#
#   merge <file.json> [file.json ...]
#       Fold {"<id>":{"mtime":..,"summary":..}} objects into the cache,
#       last-writer-wins. Used after the summarizer agents write their chunks.
#
#   render
#       Print the final aligned table from the stashed NDJSON + the cache.
#       No model involvement. This is the deliverable; the caller just lets
#       this command's stdout reach the user.
#
# Cache:  ~/.claude/.sessions-summary-cache.json
# Stash:  ${TMPDIR:-/tmp}/.cs.ndjson   (full NDJSON between misses→render)
#
# Footgun: `local` at script top level prints name=value, so all logic lives
# inside a function (see claude-sessions-extract.zsh for the gory details).

_csc_main() {
    emulate -L zsh
    setopt local_options pipefail
    unsetopt xtrace verbose 2>/dev/null
    trap - DEBUG 2>/dev/null
    unfunction TRAPDEBUG 2>/dev/null

    local here="${0:A:h}"
    local extractor="$here/claude-sessions-extract.zsh"
    [[ -f $extractor ]] || extractor="$HOME/.claude/scripts/claude-sessions-extract.zsh"
    local cache="$HOME/.claude/.sessions-summary-cache.json"
    local stash="${TMPDIR:-/tmp}/.cs.ndjson"
    [[ -f $cache ]] || print -r -- '{}' > "$cache"

    local mode=$1; shift 2>/dev/null

    case $mode in
      misses)
        # zsh -f: skip user init files (some inject a stdout logger).
        zsh -f "$extractor" "$@" > "$stash" 2>/dev/null
        if [[ ! -s $stash ]]; then
            print -r -- '{"error":"extractor produced no output"}'
            return 1
        fi
        # Surface a quick stat line on stderr so the caller/user can see the
        # cache working ("47 cached, 3 to summarize") without parsing JSON.
        local total miss
        total=$(wc -l < "$stash" | tr -d ' ')
        miss=$(jq -c 'select(.cached==false)' "$stash" | wc -l | tr -d ' ')
        print -r -- "[$((total - miss))/$total cached, $miss to summarize]" >&2
        # Only the misses go to the model, trimmed to what it needs.
        jq -c 'select(.cached==false) | {id, mtime, project, prompts}' "$stash"
        ;;

      merge)
        if (( $# == 0 )); then
            print -r -- "merge: no input files" >&2; return 1
        fi
        local f
        for f in "$@"; do
            [[ -f $f ]] || { print -r -- "merge: missing $f" >&2; return 1; }
            jq -e . "$f" >/dev/null 2>&1 || { print -r -- "merge: invalid JSON in $f" >&2; return 1; }
        done
        # cache * f1 * f2 ... — later objects win on key collision.
        jq -s 'reduce .[] as $o ({}; . * $o)' "$cache" "$@" > "$cache.tmp" \
            && mv "$cache.tmp" "$cache" \
            && print -r -- "merged $# file(s) into cache ($(jq 'length' "$cache") entries)"
        ;;

      render)
        if [[ ! -s $stash ]]; then
            print -r -- "render: no stashed NDJSON at $stash (run 'misses' first)" >&2
            return 1
        fi
        printf '%-16s  %-7s  %-36s  %-16s  %-32s  %s\n' \
            MODIFIED SIZE SESSION PROJECT BRANCH PREVIEW
        printf '%-16s  %-7s  %-36s  %-16s  %-32s  %s\n' \
            ---------------- ------- "------------------------------------" \
            ---------------- -------------------------------- \
            --------------------------------------------
        # Pull the live cache once; fill any null summary from it.
        jq -r --slurpfile c "$cache" '
            ($c[0]) as $cache
            | [.when, .size_h, .id, .project, .branch,
               (.summary // $cache[.id].summary // "(pending summary)")]
            | @tsv
        ' "$stash" | while IFS=$'\t' read -r when size sess proj branch prev; do
            (( ${#proj}   > 16 )) && proj="${proj[1,15]}…"
            (( ${#branch} > 32 )) && branch="${branch[1,31]}…"
            printf '%-16s  %-7s  %-36s  %-16s  %-32s  %s\n' \
                "$when" "$size" "$sess" "$proj" "$branch" "$prev"
        done
        print -r --
        print -r -- "Resume any session from a terminal with:  claude-resume <session-id-prefix>"
        ;;

      *)
        print -r -- "Usage: claude-sessions-cache.zsh {misses [args]|merge <files>|render}" >&2
        return 1 ;;
    esac
}

_csc_main "$@"

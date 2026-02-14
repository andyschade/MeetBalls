# MeetBalls — Interactive history browser TUI

# Parse session folder name into display-friendly metadata.
# Sets: _HIST_DATE_DISPLAY, _HIST_TIME_DISPLAY, _HIST_PARTICIPANTS, _HIST_DURATION
# Input: session directory path
_hist_parse_session() {
    local session_dir="$1"
    local name
    name="$(basename "$session_dir")"
    _HIST_DATE_DISPLAY=""
    _HIST_TIME_DISPLAY=""
    _HIST_PARTICIPANTS=""
    _HIST_DURATION=""

    mb_parse_session_name "$name"
    # SESSION_DATE (e.g. feb14), SESSION_YEAR (e.g. 26), SESSION_TIME (e.g. 0800)

    # Format date: "Feb 14, 2026"
    if [[ -n "$SESSION_DATE" ]] && [[ -n "$SESSION_YEAR" ]]; then
        local month_abbr="${SESSION_DATE:0:3}"
        local day="${SESSION_DATE:3}"
        # Capitalize first letter of month
        local month_cap
        month_cap="$(echo "${month_abbr:0:1}" | tr '[:lower:]' '[:upper:]')${month_abbr:1}"
        _HIST_DATE_DISPLAY="${month_cap} ${day}, 20${SESSION_YEAR}"
    fi

    # Format time: "8:00 AM" from "0800"
    if [[ -n "$SESSION_TIME" ]] && [[ ${#SESSION_TIME} -eq 4 ]]; then
        local hour="${SESSION_TIME:0:2}"
        local min="${SESSION_TIME:2:2}"
        local hour_num=$((10#$hour))
        if (( hour_num == 0 )); then
            _HIST_TIME_DISPLAY="12:${min} AM"
        elif (( hour_num < 12 )); then
            _HIST_TIME_DISPLAY="${hour_num}:${min} AM"
        elif (( hour_num == 12 )); then
            _HIST_TIME_DISPLAY="12:${min} PM"
        else
            _HIST_TIME_DISPLAY="$(( hour_num - 12 )):${min} PM"
        fi
    fi

    # Read speakers from session-state.md
    local state_file="$session_dir/session-state.md"
    if [[ -f "$state_file" ]]; then
        local in_speakers=false
        local speakers=()
        while IFS= read -r line; do
            if [[ "$line" == "## Speakers" ]]; then
                in_speakers=true
                continue
            fi
            if [[ "$line" == "##"* ]] && $in_speakers; then
                break
            fi
            if $in_speakers && [[ "$line" == "- "* ]]; then
                speakers+=("${line#- }")
            fi
        done < "$state_file"
        local result=""
        local s
        for s in "${speakers[@]}"; do
            [[ -n "$result" ]] && result="$result, "
            result="$result$s"
        done
        _HIST_PARTICIPANTS="$result"
    fi

    # Read duration from session-state.md
    if [[ -f "$state_file" ]]; then
        local in_duration=false
        while IFS= read -r line; do
            if [[ "$line" == "## Duration" ]]; then
                in_duration=true
                continue
            fi
            if [[ "$line" == "##"* ]] && $in_duration; then
                break
            fi
            if $in_duration && [[ -n "$line" ]]; then
                _HIST_DURATION="$line"
                break
            fi
        done < "$state_file"
    fi
}

# Read summary.txt from session dir.
# If missing and transcript exists, generate via claude CLI.
# Prints summary text (may be empty).
_hist_get_summary() {
    local session_dir="$1"
    local summary_file="$session_dir/summary.txt"

    if [[ -f "$summary_file" ]]; then
        cat "$summary_file"
        return 0
    fi

    # Try to generate from transcript
    local transcript="$session_dir/transcript.txt"
    if [[ -f "$transcript" ]] && mb_check_command claude; then
        local generated
        generated=$(claude -p --model sonnet \
            "Summarize this meeting transcript in 3-4 sentences. Focus on what was discussed, decisions made, and action items assigned. Be concise." \
            < "$transcript" 2>/dev/null) || true
        if [[ -n "$generated" ]]; then
            echo "$generated" > "$summary_file"
            echo "$generated"
            return 0
        fi
    fi

    return 0
}

# Render the TUI screen to stdout.
# Args: selected_index total_count sessions_array_name
_hist_render() {
    local selected=$1
    local total=$2
    local -n _sessions=$3
    local -n _summaries=$4
    local -n _dates=$5
    local -n _times=$6
    local -n _participants=$7
    local -n _durations=$8
    local term_lines=${LINES:-$(tput lines 2>/dev/null || echo 24)}

    # Clear screen
    printf '\033[2J\033[H'

    # Title bar
    printf '\n \033[1mMEETBALLS HISTORY\033[0m'
    printf '%*s' $(( term_lines > 0 ? 40 : 40 )) ""
    printf '%d sessions\n\n' "$total"

    if [[ $total -eq 0 ]]; then
        printf ' No sessions found. Run '\''meetballs live'\'' to start your first meeting.\n'
        return
    fi

    local i
    for (( i=0; i<total; i++ )); do
        local prefix="  "
        local color_on=""
        local color_off=""
        if (( i == selected )); then
            prefix=" \033[32m▸\033[0m"
            color_on="\033[32m"
            color_off="\033[0m"
        fi

        # Header: bold cyan — date, time, duration
        local header="${_dates[$i]}"
        [[ -n "${_times[$i]}" ]] && header="$header · ${_times[$i]}"
        [[ -n "${_durations[$i]}" ]] && header="$header · ${_durations[$i]}"

        printf '%b \033[1;36m┌ [%d] %s\033[0m\n' "$prefix" $(( i + 1 )) "$header"

        # Participants: dim
        if [[ -n "${_participants[$i]}" ]]; then
            printf '   \033[2m│ %s\033[0m\n' "${_participants[$i]}"
        fi

        # Summary: normal text (wrap at ~70 chars per line)
        local summary="${_summaries[$i]}"
        if [[ -n "$summary" ]]; then
            # Simple word-wrap at 70 chars
            local line=""
            local word
            while IFS= read -r -d ' ' word || [[ -n "$word" ]]; do
                if (( ${#line} + ${#word} + 1 > 70 )) && [[ -n "$line" ]]; then
                    printf '   │ %s\n' "$line"
                    line="$word"
                else
                    [[ -n "$line" ]] && line="$line $word" || line="$word"
                fi
            done <<< "$summary"
            [[ -n "$line" ]] && printf '   │ %s\n' "$line"
        fi

        # Path: dim
        printf '   \033[2m└ %s\033[0m\n' "${_sessions[$i]}"
        printf '\n'
    done

    # Footer
    printf ' ↑↓ navigate · enter select · q quit\n'
}

# Open a session directory in tmux.
_hist_open_session() {
    local session_dir="$1"
    if [[ -n "${TMUX:-}" ]]; then
        tmux new-window -c "$session_dir" -n "meetball"
    else
        tmux new-session -d -s meetball-hist -c "$session_dir"
        tmux attach-session -t meetball-hist
    fi
}

cmd_hist() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs hist

Interactive history browser for past meeting sessions.

Navigation:
  ↑/↓ or j/k   Navigate between sessions
  enter         Open session folder in a new tmux window
  q             Quit

Options:
  --help    Show this help message

Examples:
  meetballs hist
EOF
        return 0
    fi

    mb_init

    # Collect session data
    local sessions=()
    local summaries=()
    local dates=()
    local times=()
    local participants=()
    local durations=()

    local session_dir
    while IFS= read -r session_dir; do
        sessions+=("$session_dir")

        _hist_parse_session "$session_dir"
        dates+=("${_HIST_DATE_DISPLAY}")
        times+=("${_HIST_TIME_DISPLAY}")
        participants+=("${_HIST_PARTICIPANTS}")
        durations+=("${_HIST_DURATION}")

        local summary
        summary=$(_hist_get_summary "$session_dir") || true
        # Collapse to single line for display
        summary=$(echo "$summary" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
        summaries+=("$summary")
    done < <(mb_scan_sessions 2>/dev/null || true)

    local total=${#sessions[@]}
    local selected=0

    # Enter alternate screen buffer
    printf '\033[?1049h'
    # Hide cursor
    printf '\033[?25l'

    # Ensure cleanup on exit
    trap '_hist_cleanup' EXIT INT TERM

    _hist_render "$selected" "$total" sessions summaries dates times participants durations

    if [[ $total -eq 0 ]]; then
        # Wait for q to exit
        while true; do
            local key
            IFS= read -rsn1 key
            [[ "$key" == "q" || "$key" == "Q" ]] && break
        done
        return 0
    fi

    # Main input loop
    while true; do
        local key
        IFS= read -rsn1 key

        case "$key" in
            q|Q)
                break
                ;;
            k)
                # vim up
                (( selected > 0 )) && (( selected-- ))
                _hist_render "$selected" "$total" sessions summaries dates times participants durations
                ;;
            j)
                # vim down
                (( selected < total - 1 )) && (( selected++ )) || true
                _hist_render "$selected" "$total" sessions summaries dates times participants durations
                ;;
            $'\x1b')
                # Escape sequence — read next chars
                local seq
                IFS= read -rsn2 -t 0.1 seq || true
                case "$seq" in
                    '[A')
                        # Up arrow
                        (( selected > 0 )) && (( selected-- ))
                        _hist_render "$selected" "$total" sessions summaries dates times participants durations
                        ;;
                    '[B')
                        # Down arrow
                        (( selected < total - 1 )) && (( selected++ )) || true
                        _hist_render "$selected" "$total" sessions summaries dates times participants durations
                        ;;
                esac
                ;;
            '')
                # Enter key
                _hist_cleanup
                _hist_open_session "${sessions[$selected]}"
                return 0
                ;;
        esac
    done
}

_hist_cleanup() {
    # Show cursor
    printf '\033[?25h'
    # Leave alternate screen buffer
    printf '\033[?1049l'
    trap - EXIT INT TERM
}

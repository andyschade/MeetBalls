# MeetBalls — Logs command: view session logs and diagnostic dumps

cmd_logs() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs logs [options] [timestamp]

View session logs and diagnostic dumps.

Options:
  --last     Show the most recent session log
  --dump     Show diagnostic dump sections from the most recent log
  --help     Show this help message

With no arguments, lists all session logs.
With a timestamp, shows that specific session log.

Examples:
  meetballs logs
  meetballs logs --last
  meetballs logs --dump
  meetballs logs 2026-02-12T14-30-00
EOF
        return 0
    fi

    mb_init

    case "${1:-}" in
        --last)
            local latest
            latest=$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -1)
            if [[ -z "$latest" ]]; then
                mb_info "No session logs found."
                return 0
            fi
            cat "$latest"
            ;;
        --dump)
            local latest
            latest=$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -1)
            if [[ -z "$latest" ]]; then
                mb_info "No session logs found."
                return 0
            fi
            if ! grep -q "=== DIAGNOSTIC DUMP ===" "$latest"; then
                mb_info "No diagnostic dumps in most recent log."
                return 0
            fi
            sed -n '/=== DIAGNOSTIC DUMP ===/,/=== END DIAGNOSTIC DUMP ===/p' "$latest"
            ;;
        "")
            # List all sessions
            local logs
            logs=$(ls -t "$LOGS_DIR"/*.log 2>/dev/null) || true
            if [[ -z "$logs" ]]; then
                mb_info "No session logs found."
                return 0
            fi
            printf "%-28s  %-6s  %-8s  %-6s\n" "SESSION" "LOG" "STDERR" "DUMP"
            printf "%-28s  %-6s  %-8s  %-6s\n" "-------" "---" "------" "----"
            local log_file
            while IFS= read -r log_file; do
                local ts
                ts=$(basename "$log_file" .log)
                local session_dir="$LIVE_DIR/$ts"
                local has_stderr="no"
                local has_dump="no"
                if [[ -f "$session_dir/whisper-stream.stderr" ]] && [[ -s "$session_dir/whisper-stream.stderr" ]]; then
                    has_stderr="yes"
                fi
                if grep -q "=== DIAGNOSTIC DUMP ===" "$log_file" 2>/dev/null; then
                    has_dump="yes"
                fi
                printf "%-28s  %-6s  %-8s  %-6s\n" "$ts" "yes" "$has_stderr" "$has_dump"
            done <<< "$logs"
            ;;
        *)
            # Specific session by timestamp
            local log_file="$LOGS_DIR/$1.log"
            if [[ ! -f "$log_file" ]]; then
                mb_die "No log found for session: $1"
            fi
            cat "$log_file"
            ;;
    esac
}

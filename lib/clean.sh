# MeetBalls — Clean command: remove recordings to reclaim disk space

# Format bytes as human-readable size (e.g., 1.2 GB, 345.6 MB, 12.3 KB)
_clean_format_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        # GB
        local gb_x10=$(( bytes * 10 / 1073741824 ))
        printf "%d.%d GB\n" $(( gb_x10 / 10 )) $(( gb_x10 % 10 ))
    elif (( bytes >= 1048576 )); then
        # MB
        local mb_x10=$(( bytes * 10 / 1048576 ))
        printf "%d.%d MB\n" $(( mb_x10 / 10 )) $(( mb_x10 % 10 ))
    elif (( bytes >= 1024 )); then
        # KB
        local kb_x10=$(( bytes * 10 / 1024 ))
        printf "%d.%d KB\n" $(( kb_x10 / 10 )) $(( kb_x10 % 10 ))
    else
        printf "%d B\n" "$bytes"
    fi
}

cmd_clean() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs clean

Remove audio recordings from ~/.meetballs/sessions/ to reclaim disk space.
All other session artifacts (transcripts, summaries, logs) are preserved.

Options:
  --help    Show this help message

Examples:
  meetballs clean
EOF
        return 0
    fi

    mb_init

    # Scan for recordings
    local recordings=()
    local sizes=()
    local total_bytes=0

    local rec
    while IFS= read -r -d '' rec; do
        recordings+=("$rec")
        local size
        size=$(stat -c %s "$rec")
        sizes+=("$size")
        total_bytes=$(( total_bytes + size ))
    done < <(find "$SESSIONS_DIR" -mindepth 2 -maxdepth 2 -name 'recording.wav' -print0 | sort -z)

    if [[ ${#recordings[@]} -eq 0 ]]; then
        mb_info "No recordings found in ~/.meetballs/sessions/."
        return 0
    fi

    # List each recording with session name and size
    local i
    for (( i=0; i<${#recordings[@]}; i++ )); do
        local session_dir
        session_dir="$(dirname "${recordings[$i]}")"
        local session_name
        session_name="$(basename "$session_dir")"
        local human_size
        human_size=$(_clean_format_size "${sizes[$i]}")
        printf "  %s  %s\n" "$session_name" "$human_size"
    done

    echo ""
    local total_human
    total_human=$(_clean_format_size "$total_bytes")
    printf "Total: %d recording(s), %s\n" "${#recordings[@]}" "$total_human"
    echo ""

    # Prompt for confirmation
    printf "Delete all recordings? [y/N] "
    local reply
    read -r reply
    case "$reply" in
        [yY])
            for rec in "${recordings[@]}"; do
                rm -f "$rec"
            done
            mb_success "Deleted ${#recordings[@]} recording(s). Session artifacts preserved."
            ;;
        *)
            mb_info "Aborted."
            ;;
    esac
}

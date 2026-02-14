# MeetBalls — Update command: pull latest code and check for rebuild needs

cmd_update() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs update

Pull the latest MeetBalls code and check if dependencies need rebuilding.

Options:
  --help    Show this help message

Examples:
  meetballs update
EOF
        return 0
    fi

    # Resolve repo root (follow symlinks from bin/meetballs back to source)
    local repo_dir
    if [[ -n "${MEETBALLS_REPO_DIR:-}" ]]; then
        repo_dir="$MEETBALLS_REPO_DIR"
    else
        local script_real
        script_real="$(readlink -f "${BASH_SOURCE[0]}")"
        repo_dir="$(cd "$(dirname "$script_real")/.." && pwd)"
    fi

    if [[ ! -d "$repo_dir/.git" ]]; then
        mb_die "Not a git repository: $repo_dir"
    fi

    mb_init
    local state_dir="$MEETBALLS_DIR/.state"

    # 1. Pull latest code
    mb_info "Updating MeetBalls..."
    local before_hash
    before_hash=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)

    if ! git -C "$repo_dir" pull --ff-only 2>&1 | sed 's/^/  /'; then
        mb_warn "  git pull failed. You may have local changes — try: git -C $repo_dir pull --rebase"
        return 1
    fi

    local after_hash
    after_hash=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)

    if [[ "$before_hash" == "$after_hash" ]]; then
        mb_info "  Already up to date."
    else
        mb_success "  Updated: ${before_hash:0:7} -> ${after_hash:0:7}"
    fi

    # 2. Check if whisper-stream needs rebuild
    if [[ -f "$state_dir/whisper-stream-commit" ]] && mb_check_command whisper-stream; then
        local built_commit
        built_commit=$(cat "$state_dir/whisper-stream-commit")
        mb_info ""
        mb_info "whisper-stream built from commit: ${built_commit:0:12}"
        mb_info "  To rebuild, run: ./install.sh"
    fi

    # 3. Run doctor
    mb_info ""
    mb_info "Running dependency check..."
    cmd_doctor 2>/dev/null || true

    mb_info ""
    mb_success "Update complete."
}

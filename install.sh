#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="$SCRIPT_DIR/tests/libs"
BIN_TARGET="$SCRIPT_DIR/bin/meetballs"
LOCAL_BIN="$HOME/.local/bin"
MEETBALLS_DATA="${MEETBALLS_DIR:-$HOME/.meetballs}"
STATE_DIR="$MEETBALLS_DATA/.state"

# --- Handle flags ---
case "${1:-}" in
    --uninstall)
        echo "Uninstalling MeetBalls..."

        if [[ -L "$LOCAL_BIN/meetballs" ]]; then
            rm "$LOCAL_BIN/meetballs"
            echo "  Removed symlink: $LOCAL_BIN/meetballs"
        else
            echo "  No symlink found at $LOCAL_BIN/meetballs"
        fi

        if [[ -d "$STATE_DIR" ]]; then
            rm -rf "$STATE_DIR"
            echo "  Removed state: $STATE_DIR"
        fi

        if [[ -d "$MEETBALLS_DATA" ]] && [[ -t 0 ]]; then
            echo ""
            echo "Remove meeting data at $MEETBALLS_DATA? [y/N]"
            read -r answer
            case "$answer" in
                [Yy]*) rm -rf "$MEETBALLS_DATA"; echo "  Removed: $MEETBALLS_DATA" ;;
                *) echo "  Kept: $MEETBALLS_DATA" ;;
            esac
        fi

        echo ""
        echo "MeetBalls uninstalled."
        echo "Note: whisper-stream, tmux, and other system packages were not removed."
        exit 0
        ;;
    --help|-h)
        cat <<'EOF'
Usage: ./install.sh [--uninstall] [--help]

Install or uninstall MeetBalls.

Options:
  --uninstall  Remove MeetBalls symlink and optionally meeting data
  --help       Show this help message

Environment:
  WHISPER_CPP_DIR     Path to whisper.cpp source (default: ~/whisper.cpp)
  WHISPER_CPP_COMMIT  Pin whisper.cpp to this commit hash for build
  MEETBALLS_DIR       Data directory (default: ~/.meetballs)
EOF
        exit 0
        ;;
    "")
        ;; # normal install
    *)
        echo "Unknown option: $1" >&2
        echo "Run './install.sh --help' for usage." >&2
        exit 1
        ;;
esac

# --- 1. Check bash version ---
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: bash >= 4.0 required (found ${BASH_VERSION})" >&2
    exit 1
fi

# --- 2. Install bats-core test dependencies ---
echo "Installing bats-core test framework..."
mkdir -p "$LIBS_DIR"

clone_if_missing() {
    local name="$1"
    local repo="$2"
    local dest="$LIBS_DIR/$name"

    if [[ -d "$dest" ]]; then
        echo "  $name: already installed, skipping"
    else
        echo "  $name: cloning..."
        git clone --depth 1 "$repo" "$dest" 2>&1 | sed 's/^/    /'
    fi
}

clone_if_missing "bats" "https://github.com/bats-core/bats-core.git"
clone_if_missing "bats-support" "https://github.com/bats-core/bats-support.git"
clone_if_missing "bats-assert" "https://github.com/bats-core/bats-assert.git"

# --- 3. Build whisper-stream (optional, for live mode) ---
if command -v whisper-stream &>/dev/null; then
    echo ""
    echo "whisper-stream: already installed, skipping"
else
    echo ""
    echo "Building whisper-stream (for live transcription)..."

    # Check for SDL2
    if ! dpkg -s libsdl2-dev &>/dev/null; then
        if [[ -t 0 ]]; then
            echo "  libsdl2-dev not found. Install it? [Y/n]"
            read -r answer
            case "$answer" in
                [Nn]*) echo "  Skipping whisper-stream build (SDL2 required)."; SKIP_STREAM=1 ;;
                *) sudo apt install -y libsdl2-dev || { echo "  Failed to install libsdl2-dev. Skipping whisper-stream build."; SKIP_STREAM=1; } ;;
            esac
        else
            echo "  libsdl2-dev not found. Install it and re-run install.sh."
            SKIP_STREAM=1
        fi
    fi

    if [[ "${SKIP_STREAM:-}" != "1" ]]; then
        # Locate whisper.cpp source
        WHISPER_SRC=""
        for dir in "${WHISPER_CPP_DIR:-}" "$HOME/whisper.cpp" "/usr/local/src/whisper.cpp"; do
            if [[ -n "$dir" && -d "$dir" && -f "$dir/CMakeLists.txt" ]]; then
                WHISPER_SRC="$dir"
                break
            fi
        done

        if [[ -z "$WHISPER_SRC" ]]; then
            echo "  whisper.cpp source not found."
            echo "  To build whisper-stream, clone whisper.cpp and re-run install.sh:"
            echo ""
            echo "    git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp"
            echo "    ./install.sh"
            echo ""
            echo "  Or set WHISPER_CPP_DIR to your whisper.cpp checkout."
        else
            echo "  Found whisper.cpp at: $WHISPER_SRC"

            # Pin to specific commit if requested
            PREV_HEAD=""
            if [[ -n "${WHISPER_CPP_COMMIT:-}" ]] && [[ -d "$WHISPER_SRC/.git" ]]; then
                echo "  Pinning to commit: $WHISPER_CPP_COMMIT"
                PREV_HEAD=$(git -C "$WHISPER_SRC" rev-parse HEAD 2>/dev/null || echo "")
                git -C "$WHISPER_SRC" checkout "$WHISPER_CPP_COMMIT" 2>&1 | sed 's/^/    /'
            fi

            (
                cd "$WHISPER_SRC"
                cmake -B build -DWHISPER_SDL2=ON 2>&1 | sed 's/^/    /'
                cmake --build build --target stream 2>&1 | sed 's/^/    /'
            ) && {
                sudo cp "$WHISPER_SRC/build/bin/stream" /usr/local/bin/whisper-stream
                echo "  whisper-stream installed to /usr/local/bin/whisper-stream"

                # Record build state
                mkdir -p "$STATE_DIR"
                if [[ -d "$WHISPER_SRC/.git" ]]; then
                    git -C "$WHISPER_SRC" rev-parse HEAD > "$STATE_DIR/whisper-stream-commit"
                fi
            } || {
                echo "  whisper-stream build failed. You can build manually:"
                echo "    cd $WHISPER_SRC && cmake -B build -DWHISPER_SDL2=ON && cmake --build build --target stream"
            }

            # Restore previous HEAD if we changed it
            if [[ -n "$PREV_HEAD" ]] && [[ -d "$WHISPER_SRC/.git" ]]; then
                git -C "$WHISPER_SRC" checkout "$PREV_HEAD" 2>/dev/null || true
            fi
        fi
    fi
fi

# --- 4. Verify whisper model ---
verify_whisper_model() {
    local model_name="${WHISPER_MODEL:-base.en}"
    local model_file="ggml-${model_name}.bin"
    local search_dirs=(
        "${WHISPER_CPP_MODEL_DIR:-}"
        "$HOME/whisper.cpp/models"
        "$HOME/.local/share/whisper.cpp/models"
        "/usr/local/share/whisper.cpp/models"
    )

    local model_path=""
    for dir in "${search_dirs[@]}"; do
        [[ -z "$dir" ]] && continue
        if [[ -f "$dir/$model_file" ]]; then
            model_path="$dir/$model_file"
            break
        fi
    done

    if [[ -z "$model_path" ]]; then
        echo "  model:    not found (ggml-${model_name}.bin)"
        echo "            Download: bash ~/whisper.cpp/models/download-ggml-model.sh $model_name"
        return 0
    fi

    local file_size
    file_size=$(stat -c %s "$model_path" 2>/dev/null || echo "0")

    # Any model under 1MB is likely corrupt/truncated
    if (( file_size < 1048576 )); then
        echo "  model:    CORRUPT — $model_path is only $(( file_size / 1024 ))KB"
        echo "            Re-download: bash ~/whisper.cpp/models/download-ggml-model.sh $model_name"
        return 0
    fi

    echo "  model:    OK ($model_path, $(( file_size / 1048576 ))MB)"

    # Track checksum for change detection across installs
    if command -v sha256sum &>/dev/null; then
        mkdir -p "$STATE_DIR"
        local current_hash
        current_hash=$(sha256sum "$model_path" | cut -d' ' -f1)
        local hash_file="$STATE_DIR/model-${model_name}.sha256"

        if [[ -f "$hash_file" ]]; then
            local stored_hash
            stored_hash=$(cat "$hash_file")
            if [[ "$current_hash" != "$stored_hash" ]]; then
                echo "  model:    WARNING — checksum changed since last install"
                echo "            Previous: ${stored_hash:0:16}..."
                echo "            Current:  ${current_hash:0:16}..."
            fi
        fi
        echo "$current_hash" > "$hash_file"
    fi
}

echo ""
echo "Verifying whisper model..."
verify_whisper_model

# --- 5. Create symlink ---
echo ""
echo "Setting up meetballs command..."
mkdir -p "$LOCAL_BIN"

if [[ -L "$LOCAL_BIN/meetballs" ]]; then
    existing_target=$(readlink "$LOCAL_BIN/meetballs" 2>/dev/null || echo "")
    if [[ "$existing_target" == "$BIN_TARGET" ]]; then
        echo "  Symlink: already correct, skipping"
    else
        rm "$LOCAL_BIN/meetballs"
        ln -s "$BIN_TARGET" "$LOCAL_BIN/meetballs"
        echo "  Symlink: updated $LOCAL_BIN/meetballs -> $BIN_TARGET"
    fi
elif [[ -e "$LOCAL_BIN/meetballs" ]]; then
    echo "  Warning: $LOCAL_BIN/meetballs exists but is not a symlink. Skipping."
else
    ln -s "$BIN_TARGET" "$LOCAL_BIN/meetballs"
    echo "  Symlink: $LOCAL_BIN/meetballs -> $BIN_TARGET"
fi

# --- 6. Record install state ---
mkdir -p "$STATE_DIR"
echo "$SCRIPT_DIR" > "$STATE_DIR/repo-path"
date -Iseconds > "$STATE_DIR/installed-at"

# --- 7. Check PATH ---
case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *)
        echo ""
        echo "Note: $LOCAL_BIN is not in your PATH."
        echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        ;;
esac

# --- 8. Run meetballs doctor ---
echo ""
echo "Running dependency check..."
"$BIN_TARGET" doctor || true

# --- 9. Summary ---
echo ""
echo "MeetBalls installed successfully!"
echo "Run 'meetballs --help' to get started."

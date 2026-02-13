#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="$SCRIPT_DIR/tests/libs"
BIN_TARGET="$SCRIPT_DIR/bin/meetballs"
LOCAL_BIN="$HOME/.local/bin"

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
            (
                cd "$WHISPER_SRC"
                cmake -B build -DWHISPER_SDL2=ON 2>&1 | sed 's/^/    /'
                cmake --build build --target stream 2>&1 | sed 's/^/    /'
            ) && {
                sudo cp "$WHISPER_SRC/build/bin/stream" /usr/local/bin/whisper-stream
                echo "  whisper-stream installed to /usr/local/bin/whisper-stream"
            } || {
                echo "  whisper-stream build failed. You can build manually:"
                echo "    cd $WHISPER_SRC && cmake -B build -DWHISPER_SDL2=ON && cmake --build build --target stream"
            }
        fi
    fi
fi

# --- 4. Create symlink ---
echo ""
echo "Setting up meetballs command..."
mkdir -p "$LOCAL_BIN"

if [[ -L "$LOCAL_BIN/meetballs" ]]; then
    rm "$LOCAL_BIN/meetballs"
fi
ln -s "$BIN_TARGET" "$LOCAL_BIN/meetballs"
echo "  Symlink: $LOCAL_BIN/meetballs -> $BIN_TARGET"

# --- 5. Check PATH ---
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

# --- 6. Run meetballs doctor ---
echo ""
echo "Running dependency check..."
"$BIN_TARGET" doctor || true

# --- 7. Summary ---
echo ""
echo "MeetBalls installed successfully!"
echo "Run 'meetballs --help' to get started."
